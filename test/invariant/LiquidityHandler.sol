// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/LiquidityApp.sol";
import "../../src/SwapApp.sol";
import "../../src/mocks/MockERC20.sol";
import "../../src/mocks/MockV2Router.sol";

/// @dev Drives random sequences of add / remove / zap / swap from a few actors.
///      A call may legitimately revert (e.g. burning dust from a nearly empty pool
///      returns 0 tokens, as in Uniswap V2); what must hold is the resulting state.
///      Ghost counters show the runs are not vacuous.
contract LiquidityHandler is Test {
    MockERC20 public immutable dusd;
    MockERC20 public immutable ddai;
    MockV2Router public immutable router;
    LiquidityApp public immutable liquidityApp;
    SwapApp public immutable swapApp;

    address[3] public actors;
    uint256 public adds;
    uint256 public removes;
    uint256 public zaps;
    uint256 public swaps;
    uint256 public reverts;

    constructor(MockERC20 dusd_, MockERC20 ddai_, MockV2Router router_, LiquidityApp liquidityApp_, SwapApp swapApp_) {
        dusd = dusd_;
        ddai = ddai_;
        router = router_;
        liquidityApp = liquidityApp_;
        swapApp = swapApp_;

        for (uint256 i; i < actors.length; ++i) {
            address actor = makeAddr(string.concat("actor", vm.toString(i)));
            actors[i] = actor;
            deal(address(dusd_), actor, 1e12 * 1e6);
            deal(address(ddai_), actor, 1e12 * 1e18);
            vm.startPrank(actor);
            dusd_.approve(address(liquidityApp_), type(uint256).max);
            ddai_.approve(address(liquidityApp_), type(uint256).max);
            dusd_.approve(address(swapApp_), type(uint256).max);
            ddai_.approve(address(swapApp_), type(uint256).max);
            vm.stopPrank();
        }

        // Seed the pool so zap and swap always have reserves to work with.
        vm.prank(actors[0]);
        liquidityApp.addLiquidity(address(dusd), address(ddai), 1_000_000e6, 1_000_000e18, 0, 0, block.timestamp + 1);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function addLiquidity(uint256 actorSeed, uint256 amountA, uint256 amountB) external {
        address actor = _actor(actorSeed);
        amountA = bound(amountA, 1e6, 100_000e6);
        amountB = bound(amountB, 1e18, 100_000e18);
        vm.prank(actor);
        try liquidityApp.addLiquidity(address(dusd), address(ddai), amountA, amountB, 0, 0, block.timestamp + 1) {
            adds++;
        } catch {
            reverts++;
        }
    }

    function removeLiquidity(uint256 actorSeed, uint256 share) external {
        address actor = _actor(actorSeed);
        address pair = liquidityApp.getPair(address(dusd), address(ddai));
        uint256 balance = IERC20(pair).balanceOf(actor);
        // Burning a dust amount of LP returns 0 tokens and reverts, as in Uniswap V2.
        if (balance < 1e9) return;
        uint256 liquidity = bound(share, 1e9, balance);
        vm.startPrank(actor);
        IERC20(pair).approve(address(liquidityApp), liquidity);
        try liquidityApp.removeLiquidity(address(dusd), address(ddai), liquidity, 0, 0, block.timestamp + 1) {
            removes++;
        } catch {
            reverts++;
        }
        vm.stopPrank();
    }

    function zapIn(uint256 actorSeed, uint256 amount, bool dusdIn) external {
        address actor = _actor(actorSeed);
        amount = dusdIn ? bound(amount, 1e6, 50_000e6) : bound(amount, 1e18, 50_000e18);
        (address tIn, address tOther) = dusdIn ? (address(dusd), address(ddai)) : (address(ddai), address(dusd));
        vm.prank(actor);
        try liquidityApp.zapIn(tIn, tOther, amount, 0, 0, block.timestamp + 1) {
            zaps++;
        } catch {
            reverts++;
        }
    }

    function swap(uint256 actorSeed, uint256 amount, bool dusdIn) external {
        address actor = _actor(actorSeed);
        amount = dusdIn ? bound(amount, 1e6, 50_000e6) : bound(amount, 1e18, 50_000e18);
        address[] memory path = new address[](2);
        (path[0], path[1]) = dusdIn ? (address(dusd), address(ddai)) : (address(ddai), address(dusd));
        vm.prank(actor);
        try swapApp.swapTokens(amount, 0, path, block.timestamp + 1) {
            swaps++;
        } catch {
            reverts++;
        }
    }
}
