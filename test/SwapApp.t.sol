// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/SwapApp.sol";

/// @dev Tests run against a live Arbitrum mainnet fork (latest block) so
///      Uniswap V2 liquidity and token behaviour are real, but the test
///      user's balance is funded via `deal` instead of relying on a specific
///      external wallet's live balance. An earlier version pinned a fixed
///      historical block for extra determinism, but free public RPC
///      endpoints are not archive nodes and stop serving old block state
///      after a while — that broke CI once the pinned block aged out. None
///      of the assertions below depend on an exact swap output (only
///      thresholds/deltas), so forking at latest is safe and avoids relying
///      on archive-node support.
contract SwapAppTest is Test {
    SwapApp app;

    address constant V2_ROUTER = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    address user;

    function setUp() public {
        vm.createSelectFork(vm.envOr("ARBITRUM_RPC_URL", string("https://arb1.arbitrum.io/rpc")));
        app = new SwapApp(V2_ROUTER);
        user = makeAddr("user");
        deal(USDT, user, 1_000e6);
    }

    function _defaultPath() internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = USDT;
        path[1] = DAI;
    }

    function testHasBeenDeployedCorrectly() public view {
        assertEq(app.V2Router02Address(), V2_ROUTER);
    }

    function testConstructorRevertsOnZeroAddress() public {
        vm.expectRevert(SwapApp.ZeroAddress.selector);
        new SwapApp(address(0));
    }

    function testSwapTokensCorrectly() public {
        uint256 amountIn = 5e6;
        uint256 amountOutMin = 4e18;
        address[] memory path = _defaultPath();

        vm.startPrank(user);
        IERC20(USDT).approve(address(app), amountIn);

        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(user);
        uint256 daiBalanceBefore = IERC20(DAI).balanceOf(user);

        app.swapTokens(amountIn, amountOutMin, path, block.timestamp + 1000);

        assertEq(IERC20(USDT).balanceOf(user), usdtBalanceBefore - amountIn);
        assertGt(IERC20(DAI).balanceOf(user), daiBalanceBefore);
        vm.stopPrank();
    }

    function testSwapTokensEmitsSwapTokensEvent() public {
        uint256 amountIn = 5e6;
        address[] memory path = _defaultPath();

        vm.startPrank(user);
        IERC20(USDT).approve(address(app), amountIn);

        vm.expectEmit(true, true, false, false, address(app));
        emit SwapApp.SwapTokens(USDT, DAI, amountIn, 0);
        app.swapTokens(amountIn, 4e18, path, block.timestamp + 1000);
        vm.stopPrank();
    }

    function testRevertsOnPathTooShort() public {
        address[] memory path = new address[](1);
        path[0] = USDT;

        vm.startPrank(user);
        IERC20(USDT).approve(address(app), 5e6);
        vm.expectRevert(SwapApp.InvalidPath.selector);
        app.swapTokens(5e6, 0, path, block.timestamp + 1000);
        vm.stopPrank();
    }

    function testRevertsOnExpiredDeadline() public {
        address[] memory path = _defaultPath();

        vm.startPrank(user);
        IERC20(USDT).approve(address(app), 5e6);
        vm.expectRevert(bytes("UniswapV2Router: EXPIRED"));
        app.swapTokens(5e6, 0, path, block.timestamp - 1);
        vm.stopPrank();
    }

    function testRevertsOnInsufficientOutputAmount() public {
        address[] memory path = _defaultPath();

        vm.startPrank(user);
        IERC20(USDT).approve(address(app), 5e6);
        vm.expectRevert(bytes("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"));
        app.swapTokens(5e6, type(uint256).max, path, block.timestamp + 1000);
        vm.stopPrank();
    }
}
