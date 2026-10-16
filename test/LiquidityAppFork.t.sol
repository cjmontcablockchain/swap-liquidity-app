// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/LiquidityApp.sol";

/// @dev Runs against a live Arbitrum mainnet fork (latest block) so the real
///      Uniswap V2-compatible router, factory and USDT/DAI pool are exercised.
///      Like SwapAppTest, it forks at latest (free public RPCs are not archive
///      nodes) and funds the test user with `deal`; assertions use deltas and
///      thresholds only, never exact pool amounts.
contract LiquidityAppForkTest is Test {
    LiquidityApp app;

    address constant V2_ROUTER = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    address user;
    address pair;

    function setUp() public {
        vm.createSelectFork(vm.envOr("ARBITRUM_RPC_URL", string("https://arb1.arbitrum.io/rpc")));
        app = new LiquidityApp(V2_ROUTER);
        user = makeAddr("user");
        deal(USDT, user, 1_000e6);
        deal(DAI, user, 1_000e18);
        pair = app.getPair(USDT, DAI);

        vm.startPrank(user);
        IERC20(USDT).approve(address(app), type(uint256).max);
        IERC20(DAI).approve(address(app), type(uint256).max);
        vm.stopPrank();
    }

    function testHasBeenDeployedCorrectly() public view {
        assertEq(app.V2Router02Address(), V2_ROUTER);
        assertTrue(pair != address(0));
        assertEq(app.getPair(DAI, USDT), pair);
    }

    function testAddLiquidityMintsLpToCallerAndLeavesNoDust() public {
        uint256 usdtBefore = IERC20(USDT).balanceOf(user);
        uint256 daiBefore = IERC20(DAI).balanceOf(user);
        // The app's deterministic test address may already hold tokens on mainnet,
        // so check that the call leaves its balances unchanged, not zero.
        uint256 appUsdtBefore = IERC20(USDT).balanceOf(address(app));
        uint256 appDaiBefore = IERC20(DAI).balanceOf(address(app));

        vm.prank(user);
        (uint256 usedUsdt, uint256 usedDai, uint256 liquidity) =
            app.addLiquidity(USDT, DAI, 100e6, 100e18, 0, 0, block.timestamp + 1000);

        assertGt(liquidity, 0);
        assertEq(IERC20(pair).balanceOf(user), liquidity);
        assertEq(usdtBefore - IERC20(USDT).balanceOf(user), usedUsdt);
        assertEq(daiBefore - IERC20(DAI).balanceOf(user), usedDai);
        assertLe(usedUsdt, 100e6);
        assertLe(usedDai, 100e18);
        // The app keeps nothing: unused tokens are refunded, allowances cleared.
        assertEq(IERC20(USDT).balanceOf(address(app)), appUsdtBefore);
        assertEq(IERC20(DAI).balanceOf(address(app)), appDaiBefore);
        assertEq(IERC20(USDT).allowance(address(app), V2_ROUTER), 0);
        assertEq(IERC20(DAI).allowance(address(app), V2_ROUTER), 0);
    }

    function testAddThenRemoveLiquidityRoundTrip() public {
        vm.startPrank(user);
        (uint256 usedUsdt, uint256 usedDai, uint256 liquidity) =
            app.addLiquidity(USDT, DAI, 100e6, 100e18, 0, 0, block.timestamp + 1000);

        uint256 usdtBefore = IERC20(USDT).balanceOf(user);
        uint256 daiBefore = IERC20(DAI).balanceOf(user);

        IERC20(pair).approve(address(app), liquidity);
        (uint256 outUsdt, uint256 outDai) = app.removeLiquidity(USDT, DAI, liquidity, 0, 0, block.timestamp + 1000);
        vm.stopPrank();

        assertEq(IERC20(pair).balanceOf(user), 0);
        assertEq(IERC20(pair).balanceOf(address(app)), 0);
        assertEq(IERC20(USDT).balanceOf(user) - usdtBefore, outUsdt);
        assertEq(IERC20(DAI).balanceOf(user) - daiBefore, outDai);
        // Round-tripping returns (almost) what went in; allow 1% for rounding/price moves.
        assertGe(outUsdt, usedUsdt * 99 / 100);
        assertGe(outDai, usedDai * 99 / 100);
    }

    function testRevertsOnExpiredDeadline() public {
        vm.prank(user);
        vm.expectRevert(bytes("UniswapV2Router: EXPIRED"));
        app.addLiquidity(USDT, DAI, 100e6, 100e18, 0, 0, block.timestamp - 1);
    }

    function testAddLiquidityRevertsWhenMinimumNotMet() public {
        vm.prank(user);
        vm.expectRevert();
        app.addLiquidity(USDT, DAI, 100e6, 100e18, 100e6, type(uint256).max, block.timestamp + 1000);
    }

    function testRemoveLiquidityRevertsWithoutLpApproval() public {
        vm.startPrank(user);
        (,, uint256 liquidity) = app.addLiquidity(USDT, DAI, 100e6, 100e18, 0, 0, block.timestamp + 1000);
        vm.expectRevert();
        app.removeLiquidity(USDT, DAI, liquidity, 0, 0, block.timestamp + 1000);
        vm.stopPrank();
    }

    function testZapInSixUsdtIntoUsdtDaiPool() public {
        uint256 usdtBefore = IERC20(USDT).balanceOf(user);
        uint256 daiBefore = IERC20(DAI).balanceOf(user);
        uint256 appUsdtBefore = IERC20(USDT).balanceOf(address(app));
        uint256 appDaiBefore = IERC20(DAI).balanceOf(address(app));

        (uint256 swapAmount, uint256 quotedOut, uint256 quotedLiquidity) = app.quoteZapIn(USDT, DAI, 6e6);
        // About half of the 6 USDT gets swapped for DAI.
        assertGt(swapAmount, 2.5e6);
        assertLt(swapAmount, 3.5e6);
        assertGt(quotedOut, 0);

        vm.prank(user);
        uint256 liquidity =
            app.zapIn(USDT, DAI, 6e6, quotedOut * 99 / 100, quotedLiquidity * 99 / 100, block.timestamp + 1000);

        assertGt(liquidity, 0);
        assertEq(IERC20(pair).balanceOf(user), liquidity);
        // All 6 USDT were used (give or take dust) and the DAI leftover is negligible.
        assertLe(usdtBefore - IERC20(USDT).balanceOf(user), 6e6);
        assertGe(usdtBefore - IERC20(USDT).balanceOf(user), 6e6 - 6_000);
        assertLe(IERC20(DAI).balanceOf(user) - daiBefore, 0.01e18);
        // The app keeps nothing and leaves no allowance on the router.
        assertEq(IERC20(USDT).balanceOf(address(app)), appUsdtBefore);
        assertEq(IERC20(DAI).balanceOf(address(app)), appDaiBefore);
        assertEq(IERC20(USDT).allowance(address(app), V2_ROUTER), 0);
        assertEq(IERC20(DAI).allowance(address(app), V2_ROUTER), 0);
    }

    function testZapInDaiIntoUsdtDaiPoolThenRemove() public {
        vm.startPrank(user);
        uint256 liquidity = app.zapIn(DAI, USDT, 6e18, 0, 0, block.timestamp + 1000);
        assertGt(liquidity, 0);

        uint256 usdtBefore = IERC20(USDT).balanceOf(user);
        uint256 daiBefore = IERC20(DAI).balanceOf(user);
        IERC20(pair).approve(address(app), liquidity);
        app.removeLiquidity(USDT, DAI, liquidity, 0, 0, block.timestamp + 1000);
        vm.stopPrank();

        // Out and back the user holds ~6 USD of value, minus fees and price impact.
        uint256 valueBack =
            (IERC20(USDT).balanceOf(user) - usdtBefore) * 1e12 + (IERC20(DAI).balanceOf(user) - daiBefore);
        assertGt(valueBack, 5.8e18);
        assertLt(valueBack, 6.2e18);
    }

    function testZapInRevertsWhenMinLiquidityNotMet() public {
        vm.prank(user);
        vm.expectRevert(LiquidityApp.InsufficientLiquidityMinted.selector);
        app.zapIn(USDT, DAI, 6e6, 0, type(uint256).max, block.timestamp + 1000);
    }

    function testZapInRevertsWhenPairMissing() public {
        vm.prank(user);
        vm.expectRevert(LiquidityApp.PairNotFound.selector);
        app.zapIn(USDT, address(0xdead), 6e6, 0, 0, block.timestamp + 1000);
    }
}
