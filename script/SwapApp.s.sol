// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../src/SwapApp.sol";

/// @notice Deploys SwapApp pointed at a Uniswap V2-compatible router.
/// @dev Reads configuration from environment variables:
///      - PRIVATE_KEY: deployer private key.
///      - V2_ROUTER_ADDRESS: address of the Uniswap V2-compatible router.
contract SwapAppScript is Script {
    function run() external returns (SwapApp app) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address router = vm.envAddress("V2_ROUTER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);
        app = new SwapApp(router);
        vm.stopBroadcast();

        console.log("SwapApp deployed at:", address(app));
    }
}
