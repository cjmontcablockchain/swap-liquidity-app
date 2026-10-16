// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/LiquidityApp.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockV2Router.sol";

/// @dev Exposes the internal zap maths so it can be fuzzed directly.
contract LiquidityAppHarness is LiquidityApp {
    constructor(address router_) LiquidityApp(router_) {}

    function optimalSwapAmount(uint256 reserveIn_, uint256 amountIn_) external pure returns (uint256) {
        return _optimalSwapAmount(reserveIn_, amountIn_);
    }
}

/// @dev Property tests for `zapIn` against MockV2Router (no fork needed).
contract LiquidityAppFuzzTest is Test {
    MockERC20 dusd;
    MockERC20 ddai;
    MockV2Router router;
    LiquidityAppHarness app;

    address user = makeAddr("user");
    uint256 deadline;

    function setUp() public {
        dusd = new MockERC20("Demo USD", "DUSD", 6, 1_000e6);
        ddai = new MockERC20("Demo DAI", "DDAI", 18, 1_000e18);
        router = new MockV2Router();
        app = new LiquidityAppHarness(address(router));
        deadline = block.timestamp + 1000;

        dusd.mint(user, type(uint112).max);
        ddai.mint(user, type(uint112).max);

        vm.startPrank(user);
        dusd.approve(address(app), type(uint256).max);
        ddai.approve(address(app), type(uint256).max);
        vm.stopPrank();
    }

    /// The swap leg is always a strict part of the input, never all of it.
    function testFuzz_optimalSwapAmountIsBelowInput(uint256 reserveIn, uint256 amountIn) public view {
        reserveIn = bound(reserveIn, 1e3, type(uint96).max);
        amountIn = bound(amountIn, 1e3, type(uint96).max);

        uint256 swapAmount = app.optimalSwapAmount(reserveIn, amountIn);

        assertLt(swapAmount, amountIn);
        assertGt(swapAmount, 0);
    }

    /// For a small deposit relative to the pool the swap is ~half of the input
    /// (a bit under: the fee and the price impact both shift the optimum).
    function testFuzz_optimalSwapAmountApproachesHalfForSmallDeposits(uint256 reserveIn, uint256 amountIn) public view {
        reserveIn = bound(reserveIn, 1e12, type(uint96).max);
        amountIn = bound(amountIn, 1e6, reserveIn / 1e4); // deposit <= 0.01% of the pool

        uint256 swapAmount = app.optimalSwapAmount(reserveIn, amountIn);

        assertApproxEqRel(swapAmount, amountIn / 2, 0.01e18); // within 1%
    }

    /// After any zap: the app keeps nothing, the user only ever pays `amountIn`
    /// in total, the refunded dust is tiny and LP tokens were minted.
    function testFuzz_zapInLeavesNoFundsInApp(uint256 reserveDusd, uint256 reserveDdai, uint256 amountIn, bool dusdIn)
        public
    {
        reserveDusd = bound(reserveDusd, 1_000e6, 1e12 * 1e6);
        reserveDdai = bound(reserveDdai, 1_000e18, 1e12 * 1e18);
        vm.prank(user);
        app.addLiquidity(address(dusd), address(ddai), reserveDusd, reserveDdai, 0, 0, deadline);

        (MockERC20 tIn, MockERC20 tOther) = dusdIn ? (dusd, ddai) : (ddai, dusd);
        uint256 reserveIn = dusdIn ? reserveDusd : reserveDdai;
        // Between 0.0001% and 50% of the input-side reserve.
        amountIn = bound(amountIn, reserveIn / 1e6, reserveIn / 2);

        uint256 inBefore = tIn.balanceOf(user);
        uint256 otherBefore = tOther.balanceOf(user);

        vm.prank(user);
        uint256 liquidity = app.zapIn(address(tIn), address(tOther), amountIn, 0, 0, deadline);

        assertGt(liquidity, 0);
        // Nothing is left in the app, in either token or in LP tokens.
        assertEq(tIn.balanceOf(address(app)), 0);
        assertEq(tOther.balanceOf(address(app)), 0);
        assertEq(IERC20(app.getPair(address(tIn), address(tOther))).balanceOf(address(app)), 0);
        // No dangling allowances towards the router.
        assertEq(tIn.allowance(address(app), address(router)), 0);
        assertEq(tOther.allowance(address(app), address(router)), 0);
        // The user never pays more than `amountIn`, and the input dust refunded
        // is below 0.1% of the amount plus 2 wei of rounding slack.
        uint256 spent = inBefore - tIn.balanceOf(user);
        assertLe(spent, amountIn);
        assertGe(spent, amountIn - amountIn / 1000 - 2);
        // The user never loses `tOther`: they only ever get dust of it back.
        assertGe(tOther.balanceOf(user), otherBefore);
    }

    /// `quoteZapIn` predicts the LP minted by `zapIn` (same block, same reserves).
    function testFuzz_quoteZapInMatchesRealZap(uint256 reserveDusd, uint256 reserveDdai, uint256 amountIn) public {
        reserveDusd = bound(reserveDusd, 1_000e6, 1e12 * 1e6);
        reserveDdai = bound(reserveDdai, 1_000e18, 1e12 * 1e18);
        vm.prank(user);
        app.addLiquidity(address(dusd), address(ddai), reserveDusd, reserveDdai, 0, 0, deadline);
        // Not tinier than 0.01% of the pool: below that, integer rounding of a
        // few base units is already a visible fraction of the amount.
        amountIn = bound(amountIn, reserveDusd / 1e4, reserveDusd / 2);

        (,, uint256 quoted) = app.quoteZapIn(address(dusd), address(ddai), amountIn);
        vm.prank(user);
        uint256 minted = app.zapIn(address(dusd), address(ddai), amountIn, 0, 0, deadline);

        assertApproxEqRel(minted, quoted, 0.001e18); // within 0.1%
    }
}
