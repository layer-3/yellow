# Treasury

The Treasury is a secure vault for Layer-3 Foundation assets. It supports ETH and ERC-20 transfers and is protected by `Ownable2Step` to prevent accidental ownership loss.

## Transfer Function

```solidity
function transfer(
    address token,   // address(0) for ETH, otherwise ERC-20 address
    address to,      // destination address
    uint256 amount   // amount to transfer
) external onlyOwner nonReentrant;
```

- Only the owner can call `transfer()`
- For ERC-20 tokens with fee-on-transfer, the event emits the actual amount received
- `renounceOwnership()` is disabled to prevent permanently locking funds

## Ownership

The Treasury uses OpenZeppelin's `Ownable2Step`:

1. Current owner calls `transferOwnership(newOwner)`
2. New owner calls `acceptOwnership()` to complete the transfer

This two-step process prevents accidentally transferring ownership to an incorrect address.

### Ownership Models

**Foundation-owned (direct):**
- The Foundation multisig is the owner
- Can call `transfer()` directly

**Governance-owned (via TimelockController):**
- The TimelockController is the owner
- Transfers require a governance proposal: propose → vote → queue → execute
- Provides full DAO control over treasury funds

## Receiving Funds

The Treasury accepts:
- **ETH** — via the `receive()` function (just send ETH to the contract)
- **ERC-20** — via standard `transfer()` or `transferFrom()` to the contract address

## Events

| Event | Parameters | When |
|---|---|---|
| `Transferred` | `token`, `to`, `amount` | Funds moved out |
| `OwnershipTransferred` | `previousOwner`, `newOwner` | Ownership changed |
| `OwnershipTransferStarted` | `previousOwner`, `newOwner` | Transfer initiated |

## View Functions

| Function | Returns | Description |
|---|---|---|
| `name()` | `string` | Human-readable label (e.g. "Grants", "Operations") |
| `owner()` | `address` | Current owner |
| `pendingOwner()` | `address` | Address that can accept ownership (0 if none) |
