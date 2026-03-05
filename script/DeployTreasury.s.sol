// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {Treasury} from "../src/Treasury.sol";

/**
 * @title DeployTreasury
 * @notice Deploys a Treasury instance owned by the Foundation.
 *
 * Environment variables:
 *   FOUNDATION_ADDRESS — address that owns the Treasury
 *   TREASURY_NAME      — human-readable label (default: "Treasury")
 *
 * Usage:
 *   forge script script/DeployTreasury.s.sol --rpc-url <RPC> --broadcast --verify
 */
contract DeployTreasury is Script {
    function run() external {
        address foundationAddress = vm.envAddress("FOUNDATION_ADDRESS");
        string memory treasuryName = vm.envOr("TREASURY_NAME", string("Treasury"));

        vm.startBroadcast();

        Treasury treasury = new Treasury(foundationAddress, treasuryName);
        console.log("Treasury:", address(treasury), "-", treasuryName);

        vm.stopBroadcast();
    }
}
