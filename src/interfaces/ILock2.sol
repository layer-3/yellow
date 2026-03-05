// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/**
 * @title ILock2
 * @notice Single-asset vault with a time-locked withdrawal mechanism.
 *         Users lock tokens, initiate an unlock, and withdraw after the waiting period.
 *
 * State machine per user:
 *
 *         lock(amount)            unlock()             withdraw()
 *   Idle ─────────────► Locked ─────────────► Unlocking ──────────► Idle
 *                          │                      │
 *                lock(amount) adds to balance,    relock()
 *                       stays Locked              returns to Locked
 */
interface ILock2 {
    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------

    enum LockState {
        Idle,
        Locked,
        Unlocking
    }

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice The address supplied is the zero address.
    error InvalidAddress();

    /// @notice Amount must be greater than zero.
    error InvalidAmount();

    /// @notice Caller has no locked balance.
    error NotLocked();

    /// @notice unlock() was not called before withdraw(), or waiting period has not elapsed.
    error NotUnlocking();

    /// @notice Caller is already in the Unlocking state.
    error AlreadyUnlocking();

    /// @notice Waiting period has not elapsed yet.
    /// @param availableAt Timestamp when withdraw() becomes callable.
    error UnlockPeriodNotElapsed(uint256 availableAt);

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @param user The user that locked tokens.
    /// @param deposited The amount of tokens deposited in this call.
    /// @param newBalance The cumulative locked balance after this call.
    event Locked(address indexed user, uint256 deposited, uint256 newBalance);

    /// @param user The user that initiated unlock.
    /// @param balance  The full balance queued for withdrawal.
    /// @param availableAt Timestamp when withdraw() becomes callable.
    event UnlockInitiated(address indexed user, uint256 balance, uint256 availableAt);

    /// @param user The user that cancelled an unlock and relocked.
    /// @param balance The balance that was relocked.
    event Relocked(address indexed user, uint256 balance);

    /// @param user The user that withdrew.
    /// @param balance The amount withdrawn.
    event Withdrawn(address indexed user, uint256 balance);

    // -------------------------------------------------------------------------
    // View functions
    // -------------------------------------------------------------------------

    /// @notice The address of the single ERC-20 token this vault accepts.
    function asset() external view returns (address);

    /// @notice Returns the current lock state for a user.
    function lockStateOf(address user) external view returns (LockState);

    /// @notice Returns the locked balance for a user.
    function balanceOf(address user) external view returns (uint256);

    /// @notice Returns the timestamp when withdraw() becomes callable (0 if not unlocking).
    function unlockTimestampOf(address user) external view returns (uint256);

    // -------------------------------------------------------------------------
    // Mutating functions
    // -------------------------------------------------------------------------

    /// @notice Transfers `amount` tokens from the caller into the vault, crediting `target`.
    ///         Can be called multiple times to add to an existing Locked balance.
    ///         Reverts with AlreadyUnlocking if `target` is in the Unlocking state.
    function lock(uint256 amount, address target) external;

    /// @notice Starts the waiting period for the caller's full balance.
    ///         Reverts with NotLocked if the caller has no balance.
    ///         Reverts with AlreadyUnlocking if unlock() was already called.
    function unlock() external;

    /// @notice Cancels an in-progress unlock and returns to Locked state.
    ///         Restores voting power. Reverts with NotUnlocking if not unlocking.
    function relock() external;

    /// @notice Transfers the caller's full balance to `destination`.
    ///         Reverts with NotUnlocking if unlock() was not called.
    ///         Reverts with UnlockPeriodNotElapsed if the waiting period has not elapsed.
    function withdraw(address destination) external;
}
