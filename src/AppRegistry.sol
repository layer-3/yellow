// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Locker} from "./Locker.sol";
import {ISlash} from "./interfaces/ISlash.sol";

/**
 * @title AppRegistry
 * @notice Registry for app builders who post YELLOW as a service quality guarantee.
 *         Authorised adjudicators can slash a participant's balance as penalty for misbehaviour.
 *
 * @dev Access control:
 *      - `DEFAULT_ADMIN_ROLE` is held by the TimelockController (parameter administration) and
 *        can grant or revoke `ADJUDICATOR_ROLE` to multiple addresses.
 *      - `ADJUDICATOR_ROLE` holders can call `slash`.
 *
 *      No collateral weight for parameter administration — this registry is purely for
 *      collateral management and slashing. See NodeRegistry for the parameter-administration-enabled
 *      variant used by node operators.
 *
 *      Slashing can occur in both Locked and Unlocking states.
 *
 *      Adjudicators are not economically incentivised by slash outcomes by design.
 *      Dispute initiators pay the adjudicator's handling fee off-chain (similar to
 *      arbitration forums / ODRP). This avoids creating perverse incentives around
 *      decision outcomes.
 */
contract AppRegistry is Locker, ISlash, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant ADJUDICATOR_ROLE = keccak256("ADJUDICATOR_ROLE");

    /// @notice Minimum time (seconds) that must elapse between any two slash calls.
    /// @dev The cooldown is intentionally global (not per-adjudicator). It is expected to be
    ///      short. Governance can revoke the ADJUDICATOR_ROLE from abusive adjudicators.
    uint256 public slashCooldown;

    /// @notice Timestamp of the last successful slash.
    uint256 public lastSlashTimestamp;

    error SlashCooldownActive(uint256 availableAt);

    event SlashCooldownUpdated(uint256 oldCooldown, uint256 newCooldown);

    constructor(address asset_, uint256 unlockPeriod_, address admin_) Locker(asset_, unlockPeriod_) {
        if (admin_ == address(0)) revert InvalidAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    /// @notice Sets the global cooldown between slash calls.
    /// @param newCooldown The new cooldown in seconds (0 disables the cooldown).
    function setSlashCooldown(uint256 newCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldCooldown = slashCooldown;
        slashCooldown = newCooldown;
        emit SlashCooldownUpdated(oldCooldown, newCooldown);
    }

    /// @inheritdoc ISlash
    function slash(address user, uint256 amount, address recipient, bytes calldata decision)
        external
        onlyRole(ADJUDICATOR_ROLE)
        nonReentrant
    {
        uint256 _lastSlash = lastSlashTimestamp;
        uint256 _cooldown = slashCooldown;
        if (_cooldown != 0 && _lastSlash != 0) {
            uint256 availableAt = _lastSlash + _cooldown;
            require(block.timestamp >= availableAt, SlashCooldownActive(availableAt));
        }

        require(recipient != msg.sender, RecipientIsAdjudicator());
        require(recipient != user, RecipientIsUser());

        uint256 balance = _balances[user];
        require(balance != 0, InsufficientBalance());
        require(amount <= balance, InsufficientBalance());

        uint256 newBalance = balance - amount;
        _balances[user] = newBalance;

        // If entire balance is slashed, reset state to Idle
        if (newBalance == 0) {
            _unlockTimestamps[user] = 0;
        }

        lastSlashTimestamp = block.timestamp;

        IERC20(ASSET).safeTransfer(recipient, amount);

        emit Slashed(user, amount, recipient, decision);
    }
}
