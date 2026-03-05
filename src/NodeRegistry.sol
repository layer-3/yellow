// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {ILock} from "./interfaces/ILock.sol";

/**
 * @title NodeRegistry
 * @notice Node operator registry with governance voting. Operators lock YELLOW
 *         tokens to register and gain voting power in the Yellow Network DAO.
 *         Extends OZ Votes to act as the voting-power source for governance.
 *         Users must call `delegate(self)` to activate their voting power.
 *
 * @dev ASSET is immutably set to YellowToken, a standard ERC-20 deployed by the
 *      same team in the same transaction. It has a fixed supply with no mint, burn,
 *      fee-on-transfer, or rebasing mechanics. The accounting in this vault relies
 *      on that invariant.
 *
 * Workflow:
 *   1. lock(amount)  — deposit tokens; can top-up while in Locked state.
 *   2. unlock()      — start the countdown.
 *   3. withdraw()    — after the period elapses, receive the full balance.
 */
contract NodeRegistry is ILock, ReentrancyGuard, Votes {
    using SafeERC20 for IERC20;

    address public immutable ASSET;
    uint256 public immutable NODE_UNLOCK_PERIOD;

    mapping(address user => uint256 balance) internal _balances;
    mapping(address user => uint256 unlockTimestamp) internal _unlockTimestamps;

    constructor(address asset_, uint256 unlockPeriod_) EIP712("NodeRegistry", "1") {
        if (asset_ == address(0)) revert InvalidAddress();
        if (unlockPeriod_ == 0) revert InvalidAmount();
        ASSET = asset_;
        NODE_UNLOCK_PERIOD = unlockPeriod_;
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
        if (amount == 0) revert InvalidAmount();
        if (_unlockTimestamps[target] != 0) revert AlreadyUnlocking();

        uint256 balanceBefore = IERC20(ASSET).balanceOf(address(this));
        IERC20(ASSET).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(ASSET).balanceOf(address(this)) - balanceBefore;

        uint256 newBalance = _balances[target] + received;
        _balances[target] = newBalance;

        _transferVotingUnits(address(0), target, received);

        emit Locked(target, received, newBalance);
    }

    /// @inheritdoc ILock
    function unlock() external {
        uint256 balance = _balances[msg.sender];
        if (balance == 0) revert NotLocked();
        if (_unlockTimestamps[msg.sender] != 0) revert AlreadyUnlocking();

        uint256 availableAt = block.timestamp + NODE_UNLOCK_PERIOD;
        _unlockTimestamps[msg.sender] = availableAt;

        _transferVotingUnits(msg.sender, address(0), balance);

        emit UnlockInitiated(msg.sender, balance, availableAt);
    }

    /// @inheritdoc ILock
    function relock() external {
        if (_unlockTimestamps[msg.sender] == 0) revert NotUnlocking();

        uint256 balance = _balances[msg.sender];
        _unlockTimestamps[msg.sender] = 0;

        _transferVotingUnits(address(0), msg.sender, balance);

        emit Relocked(msg.sender, balance);
    }

    /// @inheritdoc ILock
    function withdraw(address destination) external nonReentrant {
        uint256 unlockTimestamp = _unlockTimestamps[msg.sender];
        if (unlockTimestamp == 0) revert NotUnlocking();
        if (block.timestamp < unlockTimestamp) revert UnlockPeriodNotElapsed(unlockTimestamp);

        uint256 amount = _balances[msg.sender];

        _balances[msg.sender] = 0;
        _unlockTimestamps[msg.sender] = 0;

        IERC20(ASSET).safeTransfer(destination, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /// @dev Returns the locked balance as voting units for the Votes system.
    function _getVotingUnits(address account) internal view override returns (uint256) {
        if (_unlockTimestamps[account] != 0) return 0;
        return _balances[account];
    }
}
