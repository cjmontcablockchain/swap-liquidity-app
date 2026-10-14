// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../src/LiquidityApp.sol";

/// @notice Deploys LiquidityApp pointed at a Uniswap V2-compatible router.
/// @dev Reads configuration from environment variables:
///      - PRIVATE_KEY: deployer private key.
///      - V2_ROUTER_ADDRESS: address of the Uniswap V2-compatible router.
contract LiquidityAppScript is Script {
    function run() external returns (LiquidityApp app) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address router = vm.envAddress("V2_ROUTER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);
        app = new LiquidityApp(router);
        vm.stopBroadcast();

        console.log("LiquidityApp deployed at:", address(app));
    }
}
