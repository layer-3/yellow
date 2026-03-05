// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";
import {NodeRegistry} from "../src/NodeRegistry.sol";
import {AppRegistry} from "../src/AppRegistry.sol";
import {YellowGovernor} from "../src/Governor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title DeployRegistry
 * @notice Deploys the registries and governance stack on top of an existing YellowToken:
 *         NodeRegistry → AppRegistry → TimelockController → YellowGovernor
 *
 * Environment variables:
 *   TOKEN_ADDRESS         — address of the already-deployed YellowToken
 *   ADJUDICATOR_ADDRESS   — initial address granted the ADJUDICATOR_ROLE in AppRegistry
 *   VOTING_DELAY          — blocks before voting starts (default: 7200 ≈ 1 day)
 *   VOTING_PERIOD         — blocks the vote stays open (default: 50400 ≈ 1 week)
 *   PROPOSAL_THRESHOLD    — min voting power to propose (default: 10_000_000e18)
 *   QUORUM_NUMERATOR      — quorum as % of locked supply (default: 4)
 *   QUORUM_FLOOR          — minimum absolute quorum in tokens (default: 100_000_000e18 = 100M YELLOW)
 *   NODE_UNLOCK_PERIOD    — NodeRegistry withdrawal waiting period in seconds (default: 1209600 = 14 days)
 *   APP_UNLOCK_PERIOD     — AppRegistry withdrawal waiting period in seconds (default: 1209600 = 14 days)
 *   TIMELOCK_DELAY        — seconds before execution (default: 172800 = 2 days)
 *
 * Usage:
 *   forge script script/DeployRegistry.s.sol --rpc-url <RPC> --broadcast --verify
 */
contract DeployRegistry is Script {
    function run() external {
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address adjudicatorAddress = vm.envAddress("ADJUDICATOR_ADDRESS");
        uint48 votingDelay = uint48(vm.envOr("VOTING_DELAY", uint256(7200)));
        uint32 votingPeriod = uint32(vm.envOr("VOTING_PERIOD", uint256(50_400)));
        uint256 proposalThreshold = vm.envOr("PROPOSAL_THRESHOLD", uint256(10_000_000 ether));
        uint256 quorumNumerator = vm.envOr("QUORUM_NUMERATOR", uint256(4));
        uint256 quorumFloor = vm.envOr("QUORUM_FLOOR", uint256(100_000_000 ether));
        uint256 unlockPeriod = vm.envOr("NODE_UNLOCK_PERIOD", uint256(14 days));
        uint256 appUnlockPeriod = vm.envOr("APP_UNLOCK_PERIOD", uint256(14 days));
        uint256 timelockDelay = vm.envOr("TIMELOCK_DELAY", uint256(172_800));

        vm.startBroadcast();

        // 1. NodeRegistry (node operators, with voting)
        NodeRegistry nodeRegistry = new NodeRegistry(tokenAddress, unlockPeriod);
        console.log("NodeRegistry:", address(nodeRegistry));

        // 2. AppRegistry (deployer as temp admin for role setup)
        AppRegistry appRegistry = new AppRegistry(tokenAddress, appUnlockPeriod, msg.sender);
        console.log("AppRegistry:", address(appRegistry));

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
            IVotes(address(nodeRegistry)),
            timelock,
            votingDelay,
            votingPeriod,
            proposalThreshold,
            quorumNumerator,
            quorumFloor
        );
        console.log("YellowGovernor:", address(governor));

        // 5. Wire roles: governor as proposer + canceller on timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // 6. Wire AppRegistry roles: grant adjudicator, transfer admin to timelock
        appRegistry.grantRole(appRegistry.ADJUDICATOR_ROLE(), adjudicatorAddress);
        appRegistry.grantRole(appRegistry.DEFAULT_ADMIN_ROLE(), address(timelock));
        appRegistry.renounceRole(appRegistry.DEFAULT_ADMIN_ROLE(), msg.sender);

        // 7. Renounce deployer admin on timelock
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), msg.sender);

        vm.stopBroadcast();

        console.log("");
        console.log("--- Registry deployment complete ---");
    }
}
