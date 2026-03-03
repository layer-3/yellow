// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/**
 * @title ISlash
 * @notice Slashing interface for registries whose participants can be penalised
 *         by an authorised adjudicator.
 */
interface ISlash {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice The user does not have enough balance to cover the slash.
    error InsufficientBalance();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @param user      The user whose balance was slashed.
    /// @param amount    The amount of tokens slashed.
    /// @param recipient The address that received the slashed tokens.
    event Slashed(address indexed user, uint256 amount, address indexed recipient);

    // -------------------------------------------------------------------------
    // Mutating functions
    // -------------------------------------------------------------------------

    /// @notice Reduces a user's locked balance and transfers the slashed tokens
    ///         to the caller. Callable only by an authorised adjudicator.
    /// @param user   The user to slash.
    /// @param amount The amount of tokens to slash.
    function slash(address user, uint256 amount) external;
}
