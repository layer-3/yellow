// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {YellowToken} from "../src/Token.sol";
import {YellowLocker} from "../src/Locker.sol";
import {YellowGovernor} from "../src/Governor.sol";
import {Treasury} from "../src/Treasury.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title Deploy
 * @notice Deploys the full Yellow governance stack:
 *         YellowToken → Locker → TimelockController → YellowGovernor → Treasury
 *
 * Environment variables:
 *   TREASURY_ADDRESS  — address that receives the initial YELLOW supply
 *   VOTING_DELAY      — blocks before voting starts (default: 7200 ≈ 1 day)
 *   VOTING_PERIOD     — blocks the vote stays open (default: 50400 ≈ 1 week)
 *   PROPOSAL_THRESHOLD — min voting power to propose (default: 10_000_000e18)
 *   QUORUM_NUMERATOR  — quorum as % of locked supply (default: 4)
 *   QUORUM_FLOOR      — minimum absolute quorum in tokens (default: 100_000_000e18 = 100M YELLOW)
 *   UNLOCK_PERIOD     — locker withdrawal waiting period in seconds (default: 1209600 = 14 days)
 *   TIMELOCK_DELAY    — seconds before execution (default: 172800 = 2 days)
 *
 * Usage:
 *   forge script script/Deploy.s.sol --rpc-url <RPC> --broadcast --verify
 */
contract Deploy is Script {
    function run() external {
        address treasuryAddress = vm.envAddress("TREASURY_ADDRESS");
        uint48 votingDelay = uint48(vm.envOr("VOTING_DELAY", uint256(7200)));
        uint32 votingPeriod = uint32(vm.envOr("VOTING_PERIOD", uint256(50_400)));
        uint256 proposalThreshold = vm.envOr("PROPOSAL_THRESHOLD", uint256(10_000_000 ether));
        uint256 quorumNumerator = vm.envOr("QUORUM_NUMERATOR", uint256(4));
        uint256 quorumFloor = vm.envOr("QUORUM_FLOOR", uint256(100_000_000 ether));
        uint256 unlockPeriod = vm.envOr("UNLOCK_PERIOD", uint256(14 days));
        uint256 timelockDelay = vm.envOr("TIMELOCK_DELAY", uint256(172_800));

        vm.startBroadcast();

        // 1. Token
        YellowToken token = new YellowToken(treasuryAddress);
        console.log("YellowToken:", address(token));

        // 2. Locker
        YellowLocker locker = new YellowLocker(address(token), unlockPeriod);
        console.log("Locker:", address(locker));

        // 3. TimelockController (deployer as temp admin, no proposers yet)
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone can execute after delay
        TimelockController timelock = new TimelockController(
            timelockDelay,
            proposers,
            executors,
            msg.sender // temp admin
        );
        console.log("TimelockController:", address(timelock));

        // 4. Governor
        YellowGovernor governor = new YellowGovernor(
            IVotes(address(locker)),
            timelock,
            votingDelay,
            votingPeriod,
            proposalThreshold,
            quorumNumerator,
            quorumFloor
        );
        console.log("YellowGovernor:", address(governor));

        // 5. Treasury (owned by deployer initially)
        Treasury treasury = new Treasury(msg.sender);
        console.log("Treasury:", address(treasury));

        // 6. Wire roles: governor as proposer + canceller on timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // 7. Transfer treasury ownership to timelock (step 1 of 2)
        treasury.transferOwnership(address(timelock));

        // 8. Schedule acceptOwnership on the timelock
        bytes memory acceptData = abi.encodeWithSignature("acceptOwnership()");
        timelock.grantRole(timelock.PROPOSER_ROLE(), msg.sender);
        timelock.schedule(address(treasury), 0, acceptData, bytes32(0), bytes32(0), timelockDelay);
        timelock.revokeRole(timelock.PROPOSER_ROLE(), msg.sender);

        // 9. Renounce deployer admin
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), msg.sender);

        vm.stopBroadcast();

        console.log("");
        console.log("--- Deployment complete ---");
        console.log("Treasury ownership transfer is pending.");
        console.log("After %s seconds, anyone can call:", timelockDelay);
        console.log("  timelock.execute(treasury, 0, acceptOwnership(), 0x0, 0x0)");
    }
}
