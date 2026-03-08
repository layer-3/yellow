// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {Treasury} from "../src/Treasury.sol";

/**
 * @title TransferTreasury
 * @notice Encodes a Treasury.transfer() call for Gnosis Safe submission.
 *
 * Environment variables:
 *   TREASURY_ADDRESS — address of the Treasury contract
 *   TOKEN_ADDRESS    — ERC-20 token address, or 0x0000000000000000000000000000000000000000 for ETH
 *   RECIPIENT        — destination address
 *   AMOUNT           — amount in YELLOW (whole tokens, 18 decimals applied automatically)
 *
 * Usage:
 *   forge script script/TransferTreasury.s.sol
 *
 * Then paste the output into Gnosis Safe → Transaction Builder:
 *   - "Enter Address": TREASURY_ADDRESS
 *   - "Enter ABI": (paste Treasury ABI or use custom calldata)
 *   - "Calldata": the hex output below
 */
contract TransferTreasury is Script {
    function run() external view {
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address token = vm.envAddress("TOKEN_ADDRESS");
        address recipient = vm.envAddress("RECIPIENT");
        uint256 amount = vm.envUint("AMOUNT") * 1e18;

        bytes memory callData = abi.encodeCall(Treasury.transfer, (token, recipient, amount));

        console.log("=== Gnosis Safe Transaction ===");
        console.log("To:", treasury);
        console.log("Value: 0");
        console.log("Calldata:");
        console.logBytes(callData);
        console.log("");
        console.log("--- Decoded ---");
        console.log("Token:", token);
        console.log("Recipient:", recipient);
        console.log("Amount (wei):", amount);
    }
}
