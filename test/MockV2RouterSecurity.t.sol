// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockV2Router.sol";
import "./mocks/ReentrantToken.sol";

/// @notice Proves that MockV2Router.swapExactTokensForTokens follows
///         checks-effects-interactions: reserves are updated *before* either
///         token transfer, so a token with a transfer hook (ERC-777-style,
///         or any non-standard ERC-20 that calls back mid-transfer) can never
///         observe a stale, pre-swap reserve value. See the comment in
///         src/mocks/MockV2Router.sol for the fix this test locks in.
contract MockV2RouterSecurityTest is Test {
    ReentrantToken rent;
    MockERC20 ddai;
    MockV2Router router;
    address attacker = makeAddr("attacker");

    uint256 constant INITIAL_RENT_RESERVE = 1_000_000e18;
    uint256 constant INITIAL_DDAI_RESERVE = 1_000_000e18;

    function setUp() public {
        rent = new ReentrantToken();
        ddai = new MockERC20("Demo DAI", "DDAI", 18, 1_000e18);
        router = new MockV2Router();

        rent.mint(address(this), INITIAL_RENT_RESERVE);
        ddai.mint(address(this), INITIAL_DDAI_RESERVE);
        rent.approve(address(router), INITIAL_RENT_RESERVE);
        ddai.approve(address(router), INITIAL_DDAI_RESERVE);
        router.addLiquidity(address(rent), address(ddai), INITIAL_RENT_RESERVE, INITIAL_DDAI_RESERVE);

        rent.mint(attacker, 10_000e18);
    }

    function _path() internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = address(rent);
        path[1] = address(ddai);
    }

    function testReservesAreUpdatedBeforeTokenPullCompletes() public {
        rent.arm(router, address(ddai));
        uint256 reserveBefore = router.reserves(address(rent), address(ddai));
        uint256 amountIn = 1_000e18;

        vm.startPrank(attacker);
        rent.approve(address(router), amountIn);
        router.swapExactTokensForTokens(amountIn, 0, _path(), attacker, block.timestamp + 1000);
        vm.stopPrank();

        assertTrue(rent.observed());
        // The hook fires mid-transfer, while control is still inside
        // swapExactTokensForTokens. If reserves were updated *after* the
        // transfer (interactions-before-effects), this would equal
        // reserveBefore. Observing the post-swap value proves the fix holds.
        assertEq(rent.reserveObservedDuringTransfer(), reserveBefore + amountIn);
    }
}
