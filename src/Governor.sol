// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {
    GovernorVotesQuorumFraction
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {GovernorPreventLateQuorum} from "@openzeppelin/contracts/governance/extensions/GovernorPreventLateQuorum.sol";
import {GovernorProposalGuardian} from "@openzeppelin/contracts/governance/extensions/GovernorProposalGuardian.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title YellowGovernor
 * @notice Protocol parameter administration for the Yellow Network.
 *         Collateral weight is derived from YELLOW tokens posted as security
 *         deposits in the NodeRegistry by active node operators.
 *         Proposals are queued through a TimelockController before execution.
 *         Enforces a minimum quorum floor so quorum never drops below a
 *         meaningful absolute value even if total locked collateral shrinks.
 *         Includes late-quorum protection to prevent last-minute manipulation
 *         of outcomes without giving other operators time to react.
 *         A proposal guardian (Foundation multisig) can cancel any proposal
 *         as an emergency brake; removable via parameter administration.
 */
contract YellowGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl,
    GovernorPreventLateQuorum,
    GovernorProposalGuardian
{
    using Checkpoints for Checkpoints.Trace208;

    Checkpoints.Trace208 private _quorumFloorHistory;

    event QuorumFloorUpdated(uint256 oldFloor, uint256 newFloor);

    error QuorumFloorExceedsTotalSupply(uint256 newFloor, uint256 totalSupply);

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
        Governor("YellowGovernor")
        GovernorSettings(votingDelay_, votingPeriod_, proposalThreshold_)
        GovernorVotes(locker_)
        GovernorVotesQuorumFraction(quorumNumerator_)
        GovernorTimelockControl(timelock_)
        GovernorPreventLateQuorum(voteExtension_)
    {
        _updateQuorumFloor(quorumFloor_);
        _setProposalGuardian(proposalGuardian_);
    }

    /// @notice Returns the current minimum absolute quorum.
    function quorumFloor() public view returns (uint256) {
        return _quorumFloorHistory.latest();
    }

    /// @notice Returns the quorum floor at a specific timepoint (snapshotted).
    function quorumFloor(uint256 timepoint) public view returns (uint256) {
        (, uint48 key, uint208 value) = _quorumFloorHistory.latestCheckpoint();
        return key <= timepoint ? value : _quorumFloorHistory.upperLookupRecent(SafeCast.toUint48(timepoint));
    }

    /// @notice Update the quorum floor. Only callable via parameter administration.
    /// @dev Reverts if newFloor exceeds the current total collateral weight supply.
    function setQuorumFloor(uint256 newFloor) public onlyGovernance {
        uint256 supply = token().getPastTotalSupply(clock() - 1);
        if (newFloor > supply) revert QuorumFloorExceedsTotalSupply(newFloor, supply);
        _updateQuorumFloor(newFloor);
    }

    function _updateQuorumFloor(uint256 newFloor) internal {
        uint256 oldFloor = quorumFloor();
        _quorumFloorHistory.push(clock(), SafeCast.toUint208(newFloor));
        emit QuorumFloorUpdated(oldFloor, newFloor);
    }

    // -------------------------------------------------------------------------
    // Required overrides (multiple inheritance resolution)
    // -------------------------------------------------------------------------

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    function quorum(uint256 blockNumber) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        uint256 fractionalQuorum = super.quorum(blockNumber);
        uint256 floor = quorumFloor(blockNumber);
        return fractionalQuorum > floor ? fractionalQuorum : floor;
    }

    function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    function proposalDeadline(uint256 proposalId)
        public
        view
        override(Governor, GovernorPreventLateQuorum)
        returns (uint256)
    {
        return super.proposalDeadline(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }

    function clock() public view override(Governor, GovernorVotes) returns (uint48) {
        return super.clock();
    }

    /// forge-lint: disable-next-line(mixed-case-function)
    function CLOCK_MODE() public view override(Governor, GovernorVotes) returns (string memory) {
        return super.CLOCK_MODE();
    }

    function _tallyUpdated(uint256 proposalId) internal override(Governor, GovernorPreventLateQuorum) {
        super._tallyUpdated(proposalId);
    }

    function _validateCancel(uint256 proposalId, address caller)
        internal
        view
        override(Governor, GovernorProposalGuardian)
        returns (bool)
    {
        return super._validateCancel(proposalId, caller);
    }

    function _getVotes(address account, uint256 timepoint, bytes memory params)
        internal
        view
        override(Governor, GovernorVotes)
        returns (uint256)
    {
        return super._getVotes(account, timepoint, params);
    }
}
