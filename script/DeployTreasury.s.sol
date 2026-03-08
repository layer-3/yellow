// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {Treasury} from "../src/Treasury.sol";

/**
 * @title DeployTreasury
 * @notice Deploys all Treasury instances, each owned by the Foundation multisig.
 *
 * Environment variables:
 *   FOUNDATION_ADDRESS — address that owns every Treasury
 *
 * Usage:
 *   forge script script/DeployTreasury.s.sol --rpc-url <RPC> --broadcast --verify
 */
contract DeployTreasury is Script {
    function run() external {
        address foundation = vm.envAddress("FOUNDATION_ADDRESS");

        string[6] memory names = [
            "Founder",
            "Community",
            "Token Sale",
            "Foundation",
            "Network",
            "Liquidity"
        ];

        vm.startBroadcast();

        for (uint256 i = 0; i < names.length; i++) {
            Treasury treasury = new Treasury(foundation, names[i]);
            console.log("Treasury:", address(treasury), "-", names[i]);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("--- Treasury deployment complete ---");
    }
}
