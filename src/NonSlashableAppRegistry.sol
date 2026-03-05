// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ILock} from "./interfaces/ILock.sol";

/**
 * @title NonSlashableAppRegistry
 * @notice Registry for Clearnet user and app owners who lock collateral.
 *
 * @dev No governance voting power — this registry is purely for collateral
 *      management. See NodeRegistry for the governance-enabled variant used
 *      by node operators.
 *
 *      ASSET is immutably set to YellowToken, a standard ERC-20 with a fixed
 *      supply and no mint, burn, fee-on-transfer, or rebasing mechanics.
 *
 * Workflow:
 *   1. lock(amount)  — deposit tokens; can top-up while in Locked state.
 *   2. unlock()      — start the countdown.
 *   3. withdraw()    — after the period elapses, receive the full balance.
 */
contract NonSlashableAppRegistry is ILock, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable ASSET;
    uint256 public immutable UNLOCK_PERIOD;

    mapping(address user => uint256 balance) internal _balances;
    mapping(address user => uint256 unlockTimestamp) internal _unlockTimestamps;

    constructor(address asset_, uint256 unlockPeriod_) {
        require(asset_ != address(0), InvalidAddress());
        require(unlockPeriod_ != 0, InvalidAmount());
        ASSET = asset_;
        UNLOCK_PERIOD = unlockPeriod_;
    }

    // -------------------------------------------------------------------------
    // ILock view functions
    // -------------------------------------------------------------------------

    /// @inheritdoc ILock
    function asset() external view returns (address) {
        return ASSET;
    }

    /// @inheritdoc ILock
    function lockStateOf(address user) external view returns (LockState) {
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

    // -------------------------------------------------------------------------
    // ILock mutating functions
    // -------------------------------------------------------------------------

    /// @inheritdoc ILock
    function lock(address target, uint256 amount) external nonReentrant {
        require(amount != 0, InvalidAmount());
        require(_unlockTimestamps[target] == 0, AlreadyUnlocking());

        uint256 balanceBefore = IERC20(ASSET).balanceOf(address(this));
        IERC20(ASSET).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(ASSET).balanceOf(address(this)) - balanceBefore;

        uint256 newBalance = _balances[target] + received;
        _balances[target] = newBalance;

        emit Locked(target, received, newBalance);
    }

    /// @inheritdoc ILock
    function unlock() external {
        address account = msg.sender;
        uint256 balance = _balances[account];
        require(balance != 0, NotLocked());
        require(_unlockTimestamps[account] == 0, AlreadyUnlocking());

        uint256 availableAt = block.timestamp + UNLOCK_PERIOD;
        _unlockTimestamps[account] = availableAt;

        emit UnlockInitiated(account, balance, availableAt);
    }

    /// @inheritdoc ILock
    function relock() external {
        address account = msg.sender;
        require(_unlockTimestamps[account] != 0, NotUnlocking());

        uint256 balance = _balances[account];
        _unlockTimestamps[account] = 0;

        emit Relocked(account, balance);
    }

    /// @inheritdoc ILock
    function withdraw(address destination) external nonReentrant {
        address account = msg.sender;
        uint256 unlockTimestamp = _unlockTimestamps[account];
        require(unlockTimestamp != 0, NotUnlocking());
        require(block.timestamp >= unlockTimestamp, UnlockPeriodNotElapsed(unlockTimestamp));

        uint256 amount = _balances[account];

        _balances[account] = 0;
        _unlockTimestamps[account] = 0;

        IERC20(ASSET).safeTransfer(destination, amount);

        emit Withdrawn(account, amount);
    }
}
