// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ILock} from "./interfaces/ILock.sol";

/**
 * @title Locker
 * @notice Abstract single-asset vault with a time-locked withdrawal mechanism.
 *         Subcontracts define the unlock period and may add parameter administration or slashing logic.
 *
 * @dev ASSET is immutably set to YellowToken, a standard ERC-20 with a fixed supply
 *      and no mint, burn, fee-on-transfer, or rebasing mechanics.
 *
 * Workflow:
 *   1. lock(amount)  — deposit tokens; can top-up while in Locked state.
 *   2. unlock()      — start the countdown.
 *   3. withdraw()    — after the period elapses, receive the full balance.
 */
abstract contract Locker is ILock, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable ASSET;
    uint256 public immutable UNLOCK_PERIOD;

    mapping(address user => uint256 balance) internal _balances;
    mapping(address user => uint256 unlockTimestamp) internal _unlockTimestamps;

    constructor(address asset_, uint256 unlockPeriod_) {
        if (asset_ == address(0)) revert InvalidAddress();
        if (unlockPeriod_ == 0) revert InvalidPeriod();
        ASSET = asset_;
        UNLOCK_PERIOD = unlockPeriod_;
    }

    /// @inheritdoc ILock
    function asset() external view returns (address) {
        return ASSET;
    }

    /// @inheritdoc ILock
    function lockStateOf(address user) public view returns (LockState) {
        if (_balances[user] == 0) return LockState.Idle;
        if (_unlockTimestamps[user] == 0) return LockState.Locked;
        return LockState.Unlocking;
    }

    /// @inheritdoc ILock
    function balanceOf(address user) external view returns (uint256) {
        return _balances[user];
    }

    /// @inheritdoc ILock
    function unlockTimestampOf(address user) external view returns (uint256) {
        return _unlockTimestamps[user];
    }

    /// @inheritdoc ILock
    function lock(address target, uint256 amount) external nonReentrant {
        if (target == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (_unlockTimestamps[target] != 0) revert AlreadyUnlocking();

        uint256 balanceBefore = IERC20(ASSET).balanceOf(address(this));
        IERC20(ASSET).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(ASSET).balanceOf(address(this)) - balanceBefore;

        uint256 newBalance = _balances[target] + received;
        _balances[target] = newBalance;

        _afterLock(target, received);

        emit Locked(target, received, newBalance);
    }

    /// @inheritdoc ILock
    function unlock() external {
        address account = msg.sender;
        uint256 balance = _balances[account];
        if (balance == 0) revert NotLocked();
        if (_unlockTimestamps[account] != 0) revert AlreadyUnlocking();

        uint256 availableAt = block.timestamp + UNLOCK_PERIOD;
        _unlockTimestamps[account] = availableAt;

        _afterUnlock(account, balance);

        emit UnlockInitiated(account, balance, availableAt);
    }

    /// @inheritdoc ILock
    function relock() external {
        address account = msg.sender;
        if (_unlockTimestamps[account] == 0) revert NotUnlocking();

        uint256 balance = _balances[account];
        _unlockTimestamps[account] = 0;

        _afterRelock(account, balance);

        emit Relocked(account, balance);
    }

    /// @inheritdoc ILock
    function withdraw(address destination) external nonReentrant {
        address account = msg.sender;
        uint256 unlockTimestamp = _unlockTimestamps[account];
        if (unlockTimestamp == 0) revert NotUnlocking();
        if (block.timestamp < unlockTimestamp) revert UnlockPeriodNotElapsed(unlockTimestamp);

        uint256 amount = _balances[account];

        _balances[account] = 0;
        _unlockTimestamps[account] = 0;

        IERC20(ASSET).safeTransfer(destination, amount);

        emit Withdrawn(account, destination, amount);
    }

    /// @dev Hook called after tokens are locked. Override to add custom logic (e.g. collateral weight).
    function _afterLock(address target, uint256 amount) internal virtual {}

    /// @dev Hook called after unlock is initiated. Override to add custom logic.
    function _afterUnlock(address account, uint256 balance) internal virtual {}

    /// @dev Hook called after relock. Override to add custom logic.
    function _afterRelock(address account, uint256 balance) internal virtual {}
}
