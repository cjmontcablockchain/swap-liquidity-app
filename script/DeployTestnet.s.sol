// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../src/SwapApp.sol";
import "../src/LiquidityApp.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockV2Router.sol";

/// @notice Deploys the full testnet demo stack: two faucet-mintable ERC-20s,
///         a self-contained constant-product AMM router, an initial liquidity
///         seed, and SwapApp + LiquidityApp pointed at that router.
/// @dev Reads PRIVATE_KEY from the environment. All deployed addresses are
///      printed so they can be copied into web/.env for the frontend.
contract DeployTestnetScript is Script {
    uint256 constant INITIAL_LIQUIDITY_DUSD = 1_000_000e6;
    uint256 constant INITIAL_LIQUIDITY_DDAI = 1_000_000e18;
    uint256 constant FAUCET_AMOUNT_DUSD = 1_000e6;
    uint256 constant FAUCET_AMOUNT_DDAI = 1_000e18;

    function run()
        external
        returns (MockERC20 dusd, MockERC20 ddai, MockV2Router router, SwapApp app, LiquidityApp liquidityApp)
    {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        dusd = new MockERC20("Demo USD", "DUSD", 6, FAUCET_AMOUNT_DUSD);
        ddai = new MockERC20("Demo DAI", "DDAI", 18, FAUCET_AMOUNT_DDAI);
        router = new MockV2Router();
        app = new SwapApp(address(router));
        liquidityApp = new LiquidityApp(address(router));

        dusd.mint(deployer, INITIAL_LIQUIDITY_DUSD);
        ddai.mint(deployer, INITIAL_LIQUIDITY_DDAI);
        dusd.approve(address(router), INITIAL_LIQUIDITY_DUSD);
        ddai.approve(address(router), INITIAL_LIQUIDITY_DDAI);
        router.addLiquidity(
            address(dusd),
            address(ddai),
            INITIAL_LIQUIDITY_DUSD,
            INITIAL_LIQUIDITY_DDAI,
            0,
            0,
            deployer,
            block.timestamp + 1 hours
        );

        vm.stopBroadcast();

        console.log("DUSD   deployed at:", address(dusd));
        console.log("DDAI   deployed at:", address(ddai));
        console.log("Router deployed at:", address(router));
        console.log("SwapApp deployed at:", address(app));
        console.log("LiquidityApp deployed at:", address(liquidityApp));
        console.log("LP token (DUSD/DDAI) at:", router.getPair(address(dusd), address(ddai)));
    }
}
