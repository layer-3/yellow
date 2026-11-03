// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {Treasury} from "../src/Treasury.sol";

/**
 * @title DeployTreasuryXRPL
 * @notice Deploys the Treasury used to lock tokens bridged to XRPL.
 *
 * Environment variables:
 *   FOUNDATION_ADDRESS — address that owns the Treasury (Foundation multisig)
 *
 * Usage:
 *   forge script script/DeployTreasuryXRPL.s.sol --rpc-url <RPC> --broadcast --verify
 */
contract DeployTreasuryXRPL is Script {
    function run() external {
        address foundation = vm.envAddress("FOUNDATION_ADDRESS");

        vm.startBroadcast();

        Treasury treasury = new Treasury(foundation, "Bridged Tokens XRPL");
        console.log("Treasury (Bridged Tokens XRPL):", address(treasury));
        console.log("Owner:", treasury.owner());

        vm.stopBroadcast();
    }
}
