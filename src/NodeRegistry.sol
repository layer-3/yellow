// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {Locker} from "./Locker.sol";

/**
 * @title NodeRegistry
 * @notice Node operator registry with governance voting. Operators lock YELLOW
 *         tokens to register and gain voting power in the Yellow Network DAO.
 *         Extends OZ Votes to act as the voting-power source for governance.
 *         Auto-self-delegates on first lock so voting power is immediately active.
 *
 * @dev Voting units are granted on lock and removed on unlock/relock via hooks.
 */
contract NodeRegistry is Locker, Votes {
    constructor(address asset_, uint256 unlockPeriod_) Locker(asset_, unlockPeriod_) EIP712("NodeRegistry", "1") {}

    function _afterLock(address target, uint256 amount) internal override {
        // Transfer voting units first — when delegate is address(0) the vote
        // movement is a no-op, but total supply checkpoints are updated.
        _transferVotingUnits(address(0), target, amount);
        // Auto-self-delegate on first lock so undelegated locks don't inflate
        // quorum without producing votable power.
        if (delegates(target) == address(0)) {
            _delegate(target, target);
        }
    }

    function _afterUnlock(address account, uint256 balance) internal override {
        _transferVotingUnits(account, address(0), balance);
    }

    function _afterRelock(address account, uint256 balance) internal override {
        _transferVotingUnits(address(0), account, balance);
    }

    /// @dev Returns the locked balance as voting units for the Votes system.
    function _getVotingUnits(address account) internal view override returns (uint256) {
        if (_unlockTimestamps[account] != 0) return 0;
        return _balances[account];
    }
}
