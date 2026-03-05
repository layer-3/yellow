// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {NodeRegistry} from "../src/NodeRegistry.sol";
import {YellowToken} from "../src/Token.sol";
import {YellowGovernor} from "../src/Governor.sol";
import {Treasury} from "../src/Treasury.sol";
import {ILock} from "../src/interfaces/ILock.sol";

/// @dev Test harness that exposes internal quorum floor update for testing.
contract YellowGovernorHarness is YellowGovernor {
    constructor(
        IVotes locker_,
        TimelockController timelock_,
        uint48 votingDelay_,
        uint32 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumNumerator_,
        uint256 quorumFloor_,
        uint48 voteExtension_,
        address proposalGuardian_
    )
        YellowGovernor(
            locker_,
            timelock_,
            votingDelay_,
            votingPeriod_,
            proposalThreshold_,
            quorumNumerator_,
            quorumFloor_,
            voteExtension_,
            proposalGuardian_
        )
    {}

    function updateQuorumFloorUnsafe(uint256 newFloor) external {
        _updateQuorumFloor(newFloor);
    }
}

contract YellowGovernorTest is Test {
    YellowToken token;
    NodeRegistry locker;
    TimelockController timelock;
    YellowGovernorHarness governor;
    Treasury treasury;

    address deployer = address(1);
    address treasuryAddr = address(2);
    address foundation = address(6);
    address alice = address(3);
    address bob = address(4);

    uint48 constant VOTING_DELAY = 1; // 1 block
    uint32 constant VOTING_PERIOD = 50; // 50 blocks
    uint256 constant PROPOSAL_THRESHOLD = 0; // no threshold for tests
    uint256 constant QUORUM_NUMERATOR = 4; // 4%
    uint256 constant QUORUM_FLOOR = 50_000 ether; // low floor for tests
    uint48 constant VOTE_EXTENSION = 10; // 10 blocks for late-quorum tests
    uint256 constant TIMELOCK_DELAY = 1 days;

    uint256 constant LOCK_AMOUNT = 1_000_000 ether;

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy token
        token = new YellowToken(deployer);

        // Deploy locker (NodeRegistry)
        locker = new NodeRegistry(address(token), 14 days);

        // Deploy timelock (deployer as temp admin)
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone can execute
        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, deployer);

        // Deploy governor
        governor = new YellowGovernorHarness(
            IVotes(address(locker)),
            timelock,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            QUORUM_NUMERATOR,
            QUORUM_FLOOR,
            VOTE_EXTENSION,
            foundation // proposal guardian = Foundation multisig
        );

        // Grant governor the proposer & canceller roles on timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // Renounce deployer admin on timelock
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        // Deploy treasury owned by Foundation directly
        treasury = new Treasury(foundation, "Treasury");

        // Fund alice and bob
        require(token.transfer(alice, 10_000_000 ether));
        require(token.transfer(bob, 10_000_000 ether));

        // Send some tokens to timelock for governance tests
        require(token.transfer(address(timelock), 1_000_000 ether));

        vm.stopPrank();

        // Alice & bob approve and lock tokens, delegate to self
        vm.startPrank(alice);
        token.approve(address(locker), type(uint256).max);
        locker.lock(alice, LOCK_AMOUNT);
        locker.delegate(alice);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(locker), type(uint256).max);
        locker.lock(bob, LOCK_AMOUNT);
        locker.delegate(bob);
        vm.stopPrank();

        // Advance one block so voting power checkpoints are available
        vm.roll(block.number + 1);
    }

    // -------------------------------------------------------------------------
    // Setup verification
    // -------------------------------------------------------------------------

    function test_setup_treasuryOwnedByFoundation() public view {
        assertEq(treasury.owner(), foundation);
    }

    function test_setup_governorPointsToNodeRegistry() public view {
        assertEq(address(governor.token()), address(locker));
    }

    function test_setup_governorPointsToTimelock() public view {
        assertEq(governor.timelock(), address(timelock));
    }

    function test_setup_aliceHasVotingPower() public view {
        assertEq(locker.getVotes(alice), LOCK_AMOUNT);
    }

    // -------------------------------------------------------------------------
    // Propose
    // -------------------------------------------------------------------------

    function test_propose_createsProposal() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _dummyProposal();

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        assertTrue(proposalId != 0);
    }

    // -------------------------------------------------------------------------
    // Vote
    // -------------------------------------------------------------------------

    function test_vote_castForVote() public {
        uint256 proposalId = _createProposal();

        // Move past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1); // 1 = For

        assertTrue(governor.hasVoted(proposalId, alice));
    }

    function test_vote_revert_doubleVote() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.prank(alice);
        vm.expectRevert();
        governor.castVote(proposalId, 1);
    }

    // -------------------------------------------------------------------------
    // Proposal lifecycle
    // -------------------------------------------------------------------------

    function test_proposal_succeedsWithQuorum() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        // Both vote for
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        // Move past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
    }

    function test_proposal_defeatedMoreAgainstThanFor() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1); // For
        vm.prank(bob);
        governor.castVote(proposalId, 0); // Against

        vm.roll(block.number + VOTING_PERIOD + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    // -------------------------------------------------------------------------
    // Timelock integration
    // -------------------------------------------------------------------------

    function test_queue_movesToQueuedState() public {
        (
            uint256 proposalId,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descriptionHash
        ) = _passProposal();

        governor.queue(targets, values, calldatas, descriptionHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));
    }

    function test_execute_afterTimelockDelay() public {
        (
            uint256 proposalId,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descriptionHash
        ) = _passProposal();

        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
    }

    function test_execute_revert_beforeTimelockDelay() public {
        (, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) =
            _passProposal();

        governor.queue(targets, values, calldatas, descriptionHash);

        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);
    }

    // -------------------------------------------------------------------------
    // Treasury is Foundation-owned (not governance-controlled)
    // -------------------------------------------------------------------------

    function test_treasury_foundationCanWithdraw() public {
        uint256 amount = 100 ether;

        // Send tokens to treasury
        vm.prank(deployer);
        require(token.transfer(address(treasury), amount));

        uint256 aliceBalBefore = token.balanceOf(alice);

        // Foundation withdraws directly
        vm.prank(foundation);
        treasury.withdraw(address(token), alice, amount);

        assertEq(token.balanceOf(alice), aliceBalBefore + amount);
    }

    function test_treasury_directWithdrawReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        treasury.withdraw(address(token), alice, 1 ether);
    }

    // -------------------------------------------------------------------------
    // Unlock removes voting power from governance
    // -------------------------------------------------------------------------

    function test_unlock_beforeProposal_zeroVotingPower() public {
        // Alice unlocks before the proposal is created
        vm.prank(alice);
        locker.unlock();
        vm.roll(block.number + 1);

        // Create proposal — snapshot is taken at this block
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        // Alice votes, but her power at the snapshot block is 0
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        // Bob votes for
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        // Quorum is 4% of total supply at snapshot.
        // Total supply at snapshot = only bob's LOCK_AMOUNT (alice's was removed).
        // Bob's vote = LOCK_AMOUNT which is 100% of supply → passes quorum.
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // Verify alice had 0 weight
        (uint256 againstVotes, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertEq(forVotes, LOCK_AMOUNT); // only bob's weight
        assertEq(againstVotes, 0);
    }

    function test_unlock_afterProposal_retainsSnapshotPower() public {
        // Create proposal while both alice and bob are locked
        uint256 proposalId = _createProposal();

        // Advance past voting delay so the snapshot block is in the past
        vm.roll(block.number + VOTING_DELAY + 1);

        // Alice unlocks AFTER the snapshot block
        vm.prank(alice);
        locker.unlock();

        // Alice votes — her power at the snapshot block is still LOCK_AMOUNT
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        (, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertEq(forVotes, LOCK_AMOUNT);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
    }

    function test_unlock_bothBeforeProposal_defeatedNoQuorum() public {
        // Both alice and bob unlock before the proposal
        vm.prank(alice);
        locker.unlock();
        vm.prank(bob);
        locker.unlock();

        vm.roll(block.number + 1);

        // Create proposal — total supply at snapshot is 0
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        // Both vote for but with zero weight
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        // Quorum floor = 50_000 ether, forVotes = 0 → defeated
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_unlock_cannotInfluenceProposalCreatedBefore() public {
        // Create proposal while both are locked
        uint256 proposalId = _createProposal();

        vm.roll(block.number + VOTING_DELAY + 1);

        // Alice unlocks and then votes — snapshot predates unlock so she keeps power
        vm.prank(alice);
        locker.unlock();

        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 0); // Against

        vm.roll(block.number + VOTING_PERIOD + 1);

        // Tied at LOCK_AMOUNT each — defeated because for must exceed against
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_withdrawAndRelock_restoresVotingPower() public {
        // Alice unlocks
        vm.prank(alice);
        locker.unlock();

        vm.warp(block.timestamp + 14 days);

        // Alice withdraws and re-locks
        vm.startPrank(alice);
        locker.withdraw(alice);
        locker.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Alice's voting power is restored
        assertEq(locker.getVotes(alice), LOCK_AMOUNT);

        // Create proposal — alice has power at the snapshot
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        (, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertEq(forVotes, LOCK_AMOUNT * 2);
    }

    function test_unlock_reducesTotalSupplyAtSnapshot() public {
        // Alice unlocks — removes her voting units from total supply
        vm.prank(alice);
        locker.unlock();

        vm.roll(block.number + 2);

        // Total supply at the block after unlock should only include bob
        assertEq(locker.getPastTotalSupply(block.number - 1), LOCK_AMOUNT);
    }

    function test_unlock_fullGovernanceCycleWithUnlockedVoter() public {
        // Alice unlocks after proposal is created, full cycle still works
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _dummyProposal();

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Alice unlocks after snapshot
        vm.prank(alice);
        locker.unlock();

        // Vote
        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        // Queue
        vm.roll(block.number + VOTING_PERIOD + 1);
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        // Execute
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
    }

    function test_unlock_delegateAfterUnlock_noVotingPower() public {
        // Alice unlocks, then tries to re-delegate to bob
        vm.startPrank(alice);
        locker.unlock();
        locker.delegate(bob);
        vm.stopPrank();

        vm.roll(block.number + 1);

        // Bob should NOT gain alice's voting units — _getVotingUnits returns 0 for unlocking accounts
        // Bob keeps only his own LOCK_AMOUNT
        assertEq(locker.getVotes(bob), LOCK_AMOUNT);
    }

    // -------------------------------------------------------------------------
    // Quorum floor
    // -------------------------------------------------------------------------

    function test_quorumFloor_returnsConfiguredValue() public view {
        assertEq(governor.quorumFloor(), QUORUM_FLOOR);
    }

    function test_quorumFloor_enforcedWhenSupplyDrops() public {
        // Both unlock — fractional quorum would be 4% of 0 = 0
        vm.prank(alice);
        locker.unlock();
        vm.prank(bob);
        locker.unlock();

        vm.roll(block.number + 1);

        // Quorum should be the floor, not 0
        assertEq(governor.quorum(block.number - 1), QUORUM_FLOOR);
    }

    function test_quorumFloor_fractionalUsedWhenAboveFloor() public view {
        // 4% of 2M locked = 80_000 which is > QUORUM_FLOOR (50_000)
        uint256 expectedFractional = (LOCK_AMOUNT * 2) * QUORUM_NUMERATOR / 100;
        assertGt(expectedFractional, QUORUM_FLOOR);
        assertEq(governor.quorum(block.number - 1), expectedFractional);
    }

    function test_quorumFloor_snapshotted_floorChangeDoesNotAffectExistingProposal() public {
        // Both unlock so total supply drops to 0 — fractional quorum = 0,
        // so quorum is entirely determined by the floor.
        vm.prank(alice);
        locker.unlock();
        vm.prank(bob);
        locker.unlock();

        // Relock only alice with just enough to meet the current floor
        vm.warp(block.timestamp + 14 days);
        vm.startPrank(alice);
        locker.withdraw(alice);
        locker.lock(alice, QUORUM_FLOOR); // exactly 50_000
        vm.stopPrank();

        vm.roll(10);

        // Create proposal — snapshot taken now (floor = 50_000, supply = 50_000)
        uint256 proposalId = _createProposal();
        vm.roll(10 + VOTING_DELAY + 1); // block 12

        // Alice votes for — her 50_000 meets the floor exactly
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        // Governance raises the floor AFTER voting starts.
        // With the M-01 fix (checkpointed), this should NOT affect the existing proposal.
        // Without the fix (plain uint256), this WOULD retroactively break it.
        vm.roll(20); // advance so clock() - 1 is valid for supply check
        _setQuorumFloorDirectly(QUORUM_FLOOR * 2); // raise to 100_000

        vm.roll(10 + VOTING_DELAY + VOTING_PERIOD + 2); // past voting end

        // With snapshotted floor: quorum(snapshot) uses old floor (50_000) → proposal succeeds
        // Without snapshot: quorum(snapshot) uses new floor (100_000) → proposal defeated
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
    }

    function test_quorumFloor_snapshotted_historicalLookup() public {
        uint256 blockBefore = block.number;
        vm.roll(block.number + 10);
        assertEq(governor.quorumFloor(blockBefore), QUORUM_FLOOR);
    }

    // -------------------------------------------------------------------------
    // Late quorum protection
    // -------------------------------------------------------------------------

    function test_lateQuorum_extendsDeadlineWhenQuorumReachedLate() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        uint256 originalDeadline = governor.proposalDeadline(proposalId);

        // Advance to near the end of voting period (1 block before deadline)
        vm.roll(originalDeadline);

        // Alice casts the decisive vote that reaches quorum
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        // Deadline should be extended by VOTE_EXTENSION
        uint256 newDeadline = governor.proposalDeadline(proposalId);
        assertGt(newDeadline, originalDeadline);
    }

    function test_lateQuorum_noExtensionWhenQuorumReachedEarly() public {
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        uint256 originalDeadline = governor.proposalDeadline(proposalId);

        // Both vote immediately (far from deadline)
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        // Deadline should NOT be extended (quorum reached well before deadline)
        assertEq(governor.proposalDeadline(proposalId), originalDeadline);
    }

    function test_lateQuorum_voteExtensionConfigured() public view {
        assertEq(governor.lateQuorumVoteExtension(), VOTE_EXTENSION);
    }

    // -------------------------------------------------------------------------
    // Proposal guardian
    // -------------------------------------------------------------------------

    function test_proposalGuardian_returnsFoundation() public view {
        assertEq(governor.proposalGuardian(), foundation);
    }

    function test_proposalGuardian_canCancelProposal() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _dummyProposal();

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Guardian cancels
        vm.prank(foundation);
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Canceled));
    }

    function test_proposalGuardian_nonGuardianCannotCancel() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _dummyProposal();

        vm.prank(alice);
        governor.propose(targets, values, calldatas, description);

        // Random user cannot cancel
        vm.prank(bob);
        vm.expectRevert();
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
    }

    // -------------------------------------------------------------------------
    // Relock — governance-specific (lock state tests are in Locker.t.sol)
    // -------------------------------------------------------------------------

    function test_relock_restoresVotingPower() public {
        vm.startPrank(alice);
        locker.unlock();
        assertEq(locker.getVotes(alice), 0);

        locker.relock();
        assertEq(locker.getVotes(alice), LOCK_AMOUNT);
        vm.stopPrank();
    }

    function test_relock_topUpAfterRelock_increasesVotingPower() public {
        vm.startPrank(alice);
        locker.unlock();
        locker.relock();
        locker.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        assertEq(locker.getVotes(alice), LOCK_AMOUNT * 2);
    }

    function test_relock_unlockAgainAfterRelock_removesVotingPower() public {
        vm.startPrank(alice);
        locker.unlock();
        locker.relock();
        locker.unlock();
        vm.stopPrank();

        assertEq(locker.getVotes(alice), 0);
    }

    function test_relock_restoresVotingUnits() public {
        assertEq(locker.getVotes(alice), LOCK_AMOUNT);
        assertEq(locker.getVotes(bob), LOCK_AMOUNT);

        vm.prank(alice);
        locker.unlock();
        assertEq(locker.getVotes(alice), 0);
        assertEq(locker.getVotes(bob), LOCK_AMOUNT);

        vm.prank(alice);
        locker.relock();
        assertEq(locker.getVotes(alice), LOCK_AMOUNT);
        assertEq(locker.getVotes(bob), LOCK_AMOUNT);
    }

    function test_relock_votingPowerAvailableForProposal() public {
        // Alice unlocks
        vm.prank(alice);
        locker.unlock();

        // Alice sees a proposal coming and relocks
        vm.prank(alice);
        locker.relock();

        vm.roll(block.number + 1);

        // Create proposal — alice has voting power at snapshot
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        (, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertEq(forVotes, LOCK_AMOUNT * 2);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _dummyProposal()
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](1);
        targets[0] = address(1);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = "";
        description = "Test proposal";
    }

    function _createProposal() internal returns (uint256 proposalId) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _dummyProposal();

        vm.prank(alice);
        proposalId = governor.propose(targets, values, calldatas, description);
    }

    function _passProposal()
        internal
        returns (
            uint256 proposalId,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descriptionHash
        )
    {
        string memory description;
        (targets, values, calldatas, description) = _dummyProposal();
        descriptionHash = keccak256(bytes(description));

        vm.prank(alice);
        proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);
    }

    /// @dev Updates the quorum floor bypassing onlyGovernance for testing.
    function _setQuorumFloorDirectly(uint256 newFloor) internal {
        governor.updateQuorumFloorUnsafe(newFloor);
    }
}
