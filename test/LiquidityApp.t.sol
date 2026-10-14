// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/LiquidityApp.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockV2Router.sol";

/// @dev Runs against MockV2Router (no fork needed). The mock mirrors Uniswap V2's
///      addLiquidity/removeLiquidity semantics and LP-token approval flow.
contract LiquidityAppTest is Test {
    MockERC20 dusd;
    MockERC20 ddai;
    MockV2Router router;
    LiquidityApp app;

    address user = makeAddr("user");
    uint256 deadline;

    function setUp() public {
        dusd = new MockERC20("Demo USD", "DUSD", 6, 1_000e6);
        ddai = new MockERC20("Demo DAI", "DDAI", 18, 1_000e18);
        router = new MockV2Router();
        app = new LiquidityApp(address(router));
        deadline = block.timestamp + 1000;

        dusd.mint(user, 10_000e6);
        ddai.mint(user, 10_000e18);

        vm.startPrank(user);
        dusd.approve(address(app), type(uint256).max);
        ddai.approve(address(app), type(uint256).max);
        vm.stopPrank();
    }

    function _seed(uint256 a, uint256 b) internal returns (uint256 liquidity) {
        vm.prank(user);
        (,, liquidity) = app.addLiquidity(address(dusd), address(ddai), a, b, 0, 0, deadline);
    }

    function testConstructorRevertsOnZeroAddress() public {
        vm.expectRevert(LiquidityApp.ZeroAddress.selector);
        new LiquidityApp(address(0));
    }

    function testFirstDepositCreatesPoolAndMintsLpToCaller() public {
        uint256 liquidity = _seed(1_000e6, 1_000e18);

        address pair = app.getPair(address(dusd), address(ddai));
        assertTrue(pair != address(0));
        assertEq(app.getPair(address(ddai), address(dusd)), pair);
        assertGt(liquidity, 0);
        assertEq(IERC20(pair).balanceOf(user), liquidity);
        assertEq(router.reserves(address(dusd), address(ddai)), 1_000e6);
        assertEq(router.reserves(address(ddai), address(dusd)), 1_000e18);
    }

    function testAddLiquidityEmitsEvent() public {
        vm.expectEmit(true, true, true, false, address(app));
        emit LiquidityApp.LiquidityAdded(user, address(dusd), address(ddai), 0, 0, 0);
        _seed(1_000e6, 1_000e18);
    }

    function testAddLiquidityKeepsRatioAndRefundsExcess() public {
        _seed(1_000e6, 1_000e18);

        uint256 dusdBefore = dusd.balanceOf(user);
        uint256 ddaiBefore = ddai.balanceOf(user);

        // Offer 100 DUSD but 500 DDAI: pool ratio is 1:1 so only 100 DDAI is used.
        vm.prank(user);
        (uint256 usedA, uint256 usedB,) =
            app.addLiquidity(address(dusd), address(ddai), 100e6, 500e18, 0, 0, deadline);

        assertEq(usedA, 100e6);
        assertEq(usedB, 100e18);
        assertEq(dusdBefore - dusd.balanceOf(user), 100e6);
        assertEq(ddaiBefore - ddai.balanceOf(user), 100e18);
        // The app never keeps a balance or a dangling allowance.
        assertEq(dusd.balanceOf(address(app)), 0);
        assertEq(ddai.balanceOf(address(app)), 0);
        assertEq(ddai.allowance(address(app), address(router)), 0);
    }

    function testAddLiquidityRevertsBelowMin() public {
        _seed(1_000e6, 1_000e18);
        vm.prank(user);
        vm.expectRevert(bytes("MockV2Router: INSUFFICIENT_B_AMOUNT"));
        app.addLiquidity(address(dusd), address(ddai), 100e6, 500e18, 0, 200e18, deadline);
    }

    function testAddLiquidityRevertsOnExpiredDeadline() public {
        vm.prank(user);
        vm.expectRevert(bytes("MockV2Router: EXPIRED"));
        app.addLiquidity(address(dusd), address(ddai), 100e6, 100e18, 0, 0, block.timestamp - 1);
    }

    function testAddLiquidityRevertsOnIdenticalTokens() public {
        vm.prank(user);
        vm.expectRevert(LiquidityApp.IdenticalTokens.selector);
        app.addLiquidity(address(dusd), address(dusd), 1e6, 1e6, 0, 0, deadline);
    }

    function testRemoveLiquidityReturnsTokensAndBurnsLp() public {
        uint256 liquidity = _seed(1_000e6, 1_000e18);
        address pair = app.getPair(address(dusd), address(ddai));

        uint256 dusdBefore = dusd.balanceOf(user);
        uint256 ddaiBefore = ddai.balanceOf(user);

        vm.startPrank(user);
        IERC20(pair).approve(address(app), liquidity);
        (uint256 outA, uint256 outB) = app.removeLiquidity(address(dusd), address(ddai), liquidity, 0, 0, deadline);
        vm.stopPrank();

        assertGt(outA, 0);
        assertGt(outB, 0);
        assertEq(dusd.balanceOf(user) - dusdBefore, outA);
        assertEq(ddai.balanceOf(user) - ddaiBefore, outB);
        assertEq(IERC20(pair).balanceOf(user), 0);
        assertEq(IERC20(pair).balanceOf(address(app)), 0);
    }

    function testRemoveLiquidityRevertsWithoutLpApproval() public {
        uint256 liquidity = _seed(1_000e6, 1_000e18);
        vm.prank(user);
        vm.expectRevert();
        app.removeLiquidity(address(dusd), address(ddai), liquidity, 0, 0, deadline);
    }

    function testRemoveLiquidityRevertsAboveMin() public {
        uint256 liquidity = _seed(1_000e6, 1_000e18);
        address pair = app.getPair(address(dusd), address(ddai));

        vm.startPrank(user);
        IERC20(pair).approve(address(app), liquidity);
        vm.expectRevert(bytes("MockV2Router: INSUFFICIENT_A_AMOUNT"));
        app.removeLiquidity(address(dusd), address(ddai), liquidity, type(uint256).max, 0, deadline);
        vm.stopPrank();
    }

    function testRemoveLiquidityRevertsWhenPairMissing() public {
        vm.prank(user);
        vm.expectRevert(LiquidityApp.PairNotFound.selector);
        app.removeLiquidity(address(dusd), address(ddai), 1, 0, 0, deadline);
    }

    function testSwapFeesAccrueToLiquidityProviders() public {
        uint256 liquidity = _seed(1_000e6, 1_000e18);
        address pair = app.getPair(address(dusd), address(ddai));

        // A trader swaps through the router, growing the pool via the 0.3% fee.
        address trader = makeAddr("trader");
        dusd.mint(trader, 100e6);
        address[] memory path = new address[](2);
        path[0] = address(dusd);
        path[1] = address(ddai);
        vm.startPrank(trader);
        dusd.approve(address(router), 100e6);
        router.swapExactTokensForTokens(100e6, 0, path, trader, deadline);
        vm.stopPrank();

        uint256 dusdBefore = dusd.balanceOf(user);
        vm.startPrank(user);
        IERC20(pair).approve(address(app), liquidity);
        app.removeLiquidity(address(dusd), address(ddai), liquidity, 0, 0, deadline);
        vm.stopPrank();

        // User gets more DUSD back than the 1,000 deposited (minus the locked minimum share).
        assertGt(dusd.balanceOf(user) - dusdBefore, 1_000e6);
    }
}
