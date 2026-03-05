// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {Locker} from "./Locker.sol";

string constant NAME = "NodeRegistry";
string constant VERSION = "1.0.0";

/**
 * @title NodeRegistry
 * @notice Node operator registry. Operators post YELLOW tokens as a mandatory
 *         functional security deposit to operate clearnode infrastructure.
 *         Extends OZ Votes to provide collateral-weight accounting for
 *         protocol parameter administration by active node operators.
 *         Auto-self-delegates on first lock so collateral weight is immediately active.
 *
 * @dev Collateral weight units are granted on lock and removed on unlock/relock via hooks.
 */
contract NodeRegistry is Locker, Votes {
    constructor(address asset_, uint256 unlockPeriod_) Locker(asset_, unlockPeriod_) EIP712(NAME, VERSION) {}

    function _afterLock(address target, uint256 amount) internal override {
        // Transfer collateral weight units first — when delegate is address(0)
        // the weight movement is a no-op, but total supply checkpoints are updated.
        _transferVotingUnits(address(0), target, amount);
        // Auto-self-delegate on first lock so undelegated deposits don't inflate
        // quorum without producing usable collateral weight.
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

    /// @dev Returns the locked collateral as weight units for the OZ Votes system.
    function _getVotingUnits(address account) internal view override returns (uint256) {
        if (_unlockTimestamps[account] != 0) return 0;
        return _balances[account];
    }
}
