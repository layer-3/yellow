// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Faucet} from "../src/Faucet.sol";

/**
 * @title DeployFaucet
 * @notice Deploys the YELLOW testnet faucet.
 *         Fund it separately by transferring tokens to the faucet address.
 *
 * Environment variables:
 *   TOKEN_ADDRESS  — address of the already-deployed YellowToken
 *   DRIP_AMOUNT    — amount dispensed per drip (default: 1_000e18 = 1000 YELLOW)
 *   DRIP_COOLDOWN  — seconds between drips per address (default: 86400 = 1 day)
 *
 * Usage:
 *   forge script script/DeployFaucet.s.sol --rpc-url <RPC> --broadcast --verify
 */
contract DeployFaucet is Script {
    function run() external {
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        uint256 dripAmount = vm.envOr("DRIP_AMOUNT", uint256(1_000 ether));
        uint256 dripCooldown = vm.envOr("DRIP_COOLDOWN", uint256(1 days));

        vm.startBroadcast();

        Faucet faucet = new Faucet(IERC20(tokenAddress), dripAmount, dripCooldown);
        console.log("Faucet:", address(faucet));

        vm.stopBroadcast();
    }
}
