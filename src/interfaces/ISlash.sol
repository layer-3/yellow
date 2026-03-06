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

    /// @notice The recipient cannot be the adjudicator calling slash.
    error RecipientIsAdjudicator();

    /// @notice The recipient cannot be the slashed user.
    error RecipientIsUser();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @param user      The user whose balance was slashed.
    /// @param amount    The amount of tokens slashed.
    /// @param recipient The address that received the slashed tokens.
    /// @param decision  Off-chain reference to the dispute decision.
    event Slashed(address indexed user, uint256 amount, address indexed recipient, bytes decision);

    // -------------------------------------------------------------------------
    // Mutating functions
    // -------------------------------------------------------------------------

    /// @notice Reduces a user's locked balance and transfers the slashed tokens
    ///         to the specified recipient. Callable only by an authorised adjudicator.
    /// @param user      The user to slash.
    /// @param amount    The amount of tokens to slash.
    /// @param recipient The address that receives the slashed tokens (cannot be the caller).
    /// @param decision  Off-chain reference to the dispute decision.
    function slash(address user, uint256 amount, address recipient, bytes calldata decision) external;
}
