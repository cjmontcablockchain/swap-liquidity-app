// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockV2Router.sol";

contract MockV2RouterTest is Test {
    MockERC20 dusd;
    MockERC20 ddai;
    MockV2Router router;

    address deployer = address(this);
    address user = makeAddr("user");

    function setUp() public {
        dusd = new MockERC20("Demo USD", "DUSD", 6, 1_000e6);
        ddai = new MockERC20("Demo DAI", "DDAI", 18, 1_000e18);
        router = new MockV2Router();

        dusd.mint(deployer, 1_000_000e6);
        ddai.mint(deployer, 1_000_000e18);
        dusd.approve(address(router), 1_000_000e6);
        ddai.approve(address(router), 1_000_000e18);
        router.addLiquidity(
            address(dusd), address(ddai), 1_000_000e6, 1_000_000e18, 0, 0, deployer, block.timestamp + 1000
        );
    }

    function _path() internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = address(dusd);
        path[1] = address(ddai);
    }

    function testFaucetMintsFixedAmount() public {
        vm.prank(user);
        dusd.faucet();
        assertEq(dusd.balanceOf(user), 1_000e6);
    }

    function testMintIsRestrictedToOwner() public {
        vm.prank(user);
        vm.expectRevert();
        dusd.mint(user, 1e6);
    }

    function testAddLiquidityUpdatesReserves() public view {
        assertEq(router.reserves(address(dusd), address(ddai)), 1_000_000e6);
        assertEq(router.reserves(address(ddai), address(dusd)), 1_000_000e18);
    }

    function testGetAmountOutAppliesFee() public view {
        uint256 amountOut = router.getAmountOut(1_000e6, address(dusd), address(ddai));
        assertGt(amountOut, 0);
        assertLt(amountOut, 1_000e18);
    }

    function testSwapExactTokensForTokens() public {
        vm.startPrank(user);
        dusd.faucet();
        dusd.approve(address(router), 1_000e6);

        uint256 expectedOut = router.getAmountOut(1_000e6, address(dusd), address(ddai));
        uint256[] memory amounts =
            router.swapExactTokensForTokens(1_000e6, expectedOut, _path(), user, block.timestamp + 1000);

        assertEq(amounts[0], 1_000e6);
        assertEq(amounts[1], expectedOut);
        assertEq(ddai.balanceOf(user), expectedOut);
        assertEq(dusd.balanceOf(user), 0);
        vm.stopPrank();
    }

    function testSwapRevertsOnExpiredDeadline() public {
        vm.startPrank(user);
        dusd.faucet();
        dusd.approve(address(router), 1_000e6);
        vm.expectRevert(bytes("MockV2Router: EXPIRED"));
        router.swapExactTokensForTokens(1_000e6, 0, _path(), user, block.timestamp - 1);
        vm.stopPrank();
    }

    function testSwapRevertsOnInsufficientOutputAmount() public {
        vm.startPrank(user);
        dusd.faucet();
        dusd.approve(address(router), 1_000e6);
        vm.expectRevert(bytes("MockV2Router: INSUFFICIENT_OUTPUT_AMOUNT"));
        router.swapExactTokensForTokens(1_000e6, type(uint256).max, _path(), user, block.timestamp + 1000);
        vm.stopPrank();
    }

    function testSwapRevertsWhenNoLiquidityForPair() public {
        MockERC20 other = new MockERC20("Other", "OTH", 18, 1e18);
        address[] memory path = new address[](2);
        path[0] = address(dusd);
        path[1] = address(other);

        vm.startPrank(user);
        dusd.faucet();
        dusd.approve(address(router), 1_000e6);
        vm.expectRevert(bytes("MockV2Router: NO_LIQUIDITY"));
        router.swapExactTokensForTokens(1_000e6, 0, path, user, block.timestamp + 1000);
        vm.stopPrank();
    }
}
