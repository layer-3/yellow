// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {YellowToken} from "../src/Token.sol";

/**
 * @title DeployToken
 * @notice Deploys the YellowToken ERC20.
 *
 * Environment variables:
 *   FOUNDATION_ADDRESS — address that receives the initial YELLOW supply
 *
 * Usage:
 *   forge script script/DeployToken.s.sol --rpc-url <RPC> --broadcast --verify
 */
contract DeployToken is Script {
    function run() external {
        address foundationAddress = vm.envAddress("FOUNDATION_ADDRESS");

        vm.startBroadcast();

        YellowToken token = new YellowToken(foundationAddress);
        console.log("YellowToken:", address(token));

        vm.stopBroadcast();
    }
}
