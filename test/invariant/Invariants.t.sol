// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "./LiquidityHandler.sol";

/// @dev Whatever sequence of operations users run, `LiquidityApp` and `SwapApp`
///      never keep a balance or leave a router allowance behind (SECURITY.md).
contract InvariantsTest is Test {
    MockERC20 dusd;
    MockERC20 ddai;
    MockV2Router router;
    LiquidityApp liquidityApp;
    SwapApp swapApp;
    LiquidityHandler handler;

    function setUp() public {
        dusd = new MockERC20("Demo USD", "DUSD", 6, 1_000e6);
        ddai = new MockERC20("Demo DAI", "DDAI", 18, 1_000e18);
        router = new MockV2Router();
        liquidityApp = new LiquidityApp(address(router));
        swapApp = new SwapApp(address(router));
        handler = new LiquidityHandler(dusd, ddai, router, liquidityApp, swapApp);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = LiquidityHandler.addLiquidity.selector;
        selectors[1] = LiquidityHandler.removeLiquidity.selector;
        selectors[2] = LiquidityHandler.zapIn.selector;
        selectors[3] = LiquidityHandler.swap.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_liquidityAppHoldsNothing() public view {
        address pair = liquidityApp.getPair(address(dusd), address(ddai));
        assertEq(dusd.balanceOf(address(liquidityApp)), 0, "DUSD");
        assertEq(ddai.balanceOf(address(liquidityApp)), 0, "DDAI");
        assertEq(IERC20(pair).balanceOf(address(liquidityApp)), 0, "LP");
    }

    function invariant_swapAppHoldsNothing() public view {
        assertEq(dusd.balanceOf(address(swapApp)), 0, "DUSD");
        assertEq(ddai.balanceOf(address(swapApp)), 0, "DDAI");
    }

    function invariant_noDanglingRouterAllowances() public view {
        address pair = liquidityApp.getPair(address(dusd), address(ddai));
        assertEq(dusd.allowance(address(liquidityApp), address(router)), 0, "DUSD");
        assertEq(ddai.allowance(address(liquidityApp), address(router)), 0, "DDAI");
        assertEq(IERC20(pair).allowance(address(liquidityApp), address(router)), 0, "LP");
        assertEq(dusd.allowance(address(swapApp), address(router)), 0, "swap DUSD");
        assertEq(ddai.allowance(address(swapApp), address(router)), 0, "swap DDAI");
    }

    /// The pool never ends up with LP supply but no reserves (or the reverse).
    function invariant_poolStaysConsistent() public view {
        address pair = liquidityApp.getPair(address(dusd), address(ddai));
        bool hasSupply = IERC20(pair).totalSupply() > 0;
        bool hasReserves = router.reserves(address(dusd), address(ddai)) > 0;
        assertEq(hasSupply, hasReserves);
    }

    function invariant_callSummary() public view {
        console.log("adds/removes/zaps/swaps", handler.adds(), handler.removes(), handler.zaps());
        console.log("swaps / reverts", handler.swaps(), handler.reverts());
    }
}
