// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {YellowLocker} from "../src/Locker.sol";
import {YellowToken} from "../src/Token.sol";
import {YellowGovernor} from "../src/Governor.sol";
import {Treasury} from "../src/Treasury.sol";
import {ILock} from "../src/interfaces/ILock.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract YellowGovernorTest is Test {
    YellowToken token;
    YellowLocker locker;
    TimelockController timelock;
    YellowGovernor governor;
    Treasury treasury;

    address deployer = address(1);
    address treasuryAddr = address(2);
    address alice = address(3);
    address bob = address(4);

    uint48 constant VOTING_DELAY = 1; // 1 block
    uint32 constant VOTING_PERIOD = 50; // 50 blocks
    uint256 constant PROPOSAL_THRESHOLD = 0; // no threshold for tests
    uint256 constant QUORUM_NUMERATOR = 4; // 4%
    uint256 constant QUORUM_FLOOR = 50_000 ether; // low floor for tests
    uint256 constant TIMELOCK_DELAY = 1 days;

    uint256 constant LOCK_AMOUNT = 1_000_000 ether;

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy token
        token = new YellowToken(deployer);

        // Deploy locker
        locker = new YellowLocker(address(token), 14 days);

        // Deploy timelock (deployer as temp admin)
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone can execute
        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, deployer);

        // Deploy governor
        governor = new YellowGovernor(
            IVotes(address(locker)),
            timelock,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            QUORUM_NUMERATOR,
            QUORUM_FLOOR
        );

        // Grant governor the proposer & canceller roles on timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // Grant deployer temporary proposer role to schedule acceptOwnership
        timelock.grantRole(timelock.PROPOSER_ROLE(), deployer);

        // Deploy treasury owned by deployer, then transfer to timelock
        treasury = new Treasury(deployer, "Treasury");
        treasury.transferOwnership(address(timelock));

        // Schedule acceptOwnership on timelock
        bytes memory acceptData = abi.encodeCall(Ownable2Step.acceptOwnership, ());
        timelock.schedule(address(treasury), 0, acceptData, bytes32(0), bytes32(0), TIMELOCK_DELAY);

        // Warp past timelock delay and execute
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        timelock.execute(address(treasury), 0, acceptData, bytes32(0), bytes32(0));

        // Revoke deployer's temporary proposer role and admin
        timelock.revokeRole(timelock.PROPOSER_ROLE(), deployer);
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        // Fund alice and bob
        require(token.transfer(alice, 10_000_000 ether));
        require(token.transfer(bob, 10_000_000 ether));

        // Send some tokens to treasury for governance withdrawal tests
        require(token.transfer(address(timelock), 1_000_000 ether));

        vm.stopPrank();

        // Alice & bob approve and lock tokens, delegate to self
        vm.startPrank(alice);
        token.approve(address(locker), type(uint256).max);
        locker.lock(LOCK_AMOUNT);
        locker.delegate(alice);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(locker), type(uint256).max);
        locker.lock(LOCK_AMOUNT);
        locker.delegate(bob);
        vm.stopPrank();

        // Advance one block so voting power checkpoints are available
        vm.roll(block.number + 1);
    }

    // -------------------------------------------------------------------------
    // Setup verification
    // -------------------------------------------------------------------------

    function test_setup_treasuryOwnedByTimelock() public view {
        assertEq(treasury.owner(), address(timelock));
    }

    function test_setup_governorPointsToLocker() public view {
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
    // Treasury control via governance
    // -------------------------------------------------------------------------

    function test_governance_canWithdrawFromTreasury() public {
        uint256 amount = 100 ether;

        // Build proposal: treasury.withdraw(token, alice, amount)
        address[] memory targets = new address[](1);
        targets[0] = address(treasury);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(Treasury.withdraw, (address(token), alice, amount));
        string memory description = "Transfer tokens from treasury to alice";

        // Send tokens to treasury (via timelock which is owner)
        vm.prank(deployer);
        require(token.transfer(address(treasury), amount));

        uint256 aliceBalBefore = token.balanceOf(alice);

        // Propose
        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

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

        // Execute
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        governor.execute(targets, values, calldatas, descriptionHash);

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

        // Quorum is 4% of 0 = 0, and for votes = 0, so this passes trivially?
        // Actually OZ quorum(0 total supply) = 0, and 0 >= 0 is true.
        // But GovernorCountingSimple requires forVotes > againstVotes for success,
        // and 0 > 0 is false — so proposal is Defeated.
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
        locker.withdraw();
        locker.lock(LOCK_AMOUNT);
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

    function test_quorumFloor_defeatsProposalWhenBelowFloor() public {
        // Both unlock — total supply drops to 0
        vm.prank(alice);
        locker.unlock();
        vm.prank(bob);
        locker.unlock();

        vm.roll(block.number + 1);

        // Create proposal with 0 voting power available
        uint256 proposalId = _createProposal();
        vm.roll(block.number + VOTING_DELAY + 1);

        // Both vote for, but with 0 weight
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        // Quorum floor = 50_000 ether, forVotes = 0 → defeated
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    // -------------------------------------------------------------------------
    // Relock
    // -------------------------------------------------------------------------

    function test_relock_restoresVotingPower() public {
        vm.startPrank(alice);
        locker.unlock();
        assertEq(locker.getVotes(alice), 0);

        locker.relock();
        assertEq(locker.getVotes(alice), LOCK_AMOUNT);
        vm.stopPrank();
    }

    function test_relock_setsStateBackToLocked() public {
        vm.startPrank(alice);
        locker.unlock();
        locker.relock();
        vm.stopPrank();

        assertEq(uint256(locker.lockStateOf(alice)), uint256(ILock.LockState.Locked));
    }

    function test_relock_clearsUnlockTimestamp() public {
        vm.startPrank(alice);
        locker.unlock();
        locker.relock();
        vm.stopPrank();

        assertEq(locker.unlockTimestampOf(alice), 0);
    }

    function test_relock_emitsRelocked() public {
        vm.prank(alice);
        locker.unlock();

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(locker));
        emit ILock.Relocked(alice, LOCK_AMOUNT);
        locker.relock();
    }

    function test_relock_revert_ifNotUnlocking() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock.NotUnlocking.selector));
        locker.relock();
    }

    function test_relock_revert_ifIdle() public {
        address charlie = address(5);
        vm.prank(charlie);
        vm.expectRevert(abi.encodeWithSelector(ILock.NotUnlocking.selector));
        locker.relock();
    }

    function test_relock_allowsTopUpAfterRelock() public {
        vm.startPrank(alice);
        locker.unlock();
        locker.relock();
        locker.lock(LOCK_AMOUNT);
        vm.stopPrank();

        assertEq(locker.balanceOf(alice), LOCK_AMOUNT * 2);
        assertEq(locker.getVotes(alice), LOCK_AMOUNT * 2);
    }

    function test_relock_canUnlockAgainAfterRelock() public {
        vm.startPrank(alice);
        locker.unlock();
        locker.relock();
        locker.unlock();
        vm.stopPrank();

        assertEq(uint256(locker.lockStateOf(alice)), uint256(ILock.LockState.Unlocking));
        assertEq(locker.getVotes(alice), 0);
    }

    function test_relock_restoresVotingUnits() public {
        // Both alice and bob have votes
        assertEq(locker.getVotes(alice), LOCK_AMOUNT);
        assertEq(locker.getVotes(bob), LOCK_AMOUNT);

        // Alice unlocks — her voting power drops
        vm.prank(alice);
        locker.unlock();
        assertEq(locker.getVotes(alice), 0);
        assertEq(locker.getVotes(bob), LOCK_AMOUNT);

        // Alice relocks — her voting power restores
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
}
