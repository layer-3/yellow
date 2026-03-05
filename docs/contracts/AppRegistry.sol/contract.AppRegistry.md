# AppRegistry
[Git Source](https://github.com/layer-3/yellow/blob/b67bbac4d4ae41afab3ea9edfcd53990dc2741dd/src/AppRegistry.sol)

**Inherits:**
[Locker](/src/Locker.sol/abstract.Locker.md), [ISlash](/src/interfaces/ISlash.sol/interface.ISlash.md), AccessControl

**Title:**
AppRegistry

Registry for Clearnet users and app owners who lock collateral. Authorised adjudicators
can slash a participant's balance as penalty for misbehaviour.

Access control:
- `DEFAULT_ADMIN_ROLE` is held by governance (TimelockController) and
can grant or revoke `ADJUDICATOR_ROLE` to multiple addresses.
- `ADJUDICATOR_ROLE` holders can call `slash`.
No governance voting power — this registry is purely for collateral
management and slashing. See NodeRegistry for the governance-enabled
variant used by node operators.
Slashing can occur in both Locked and Unlocking states.


## State Variables
### ADJUDICATOR_ROLE

```solidity
bytes32 public constant ADJUDICATOR_ROLE = keccak256("ADJUDICATOR_ROLE")
```


### slashCooldown
Minimum time (seconds) that must elapse between any two slash calls.


```solidity
uint256 public slashCooldown
```


### lastSlashTimestamp
Timestamp of the last successful slash.


```solidity
uint256 public lastSlashTimestamp
```


## Functions
### constructor


```solidity
constructor(address asset_, uint256 unlockPeriod_, address admin_) Locker(asset_, unlockPeriod_);
```

### setSlashCooldown

Sets the global cooldown between slash calls.


```solidity
function setSlashCooldown(uint256 newCooldown) external onlyRole(DEFAULT_ADMIN_ROLE);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newCooldown`|`uint256`|The new cooldown in seconds (0 disables the cooldown).|


### slash

Reduces a user's locked balance and transfers the slashed tokens
to the specified recipient. Callable only by an authorised adjudicator.


```solidity
function slash(address user, uint256 amount, address recipient, bytes calldata decision)
    external
    onlyRole(ADJUDICATOR_ROLE)
    nonReentrant;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|     The user to slash.|
|`amount`|`uint256`|   The amount of tokens to slash.|
|`recipient`|`address`|The address that receives the slashed tokens (cannot be the caller).|
|`decision`|`bytes`| Off-chain reference to the dispute decision.|


## Events
### SlashCooldownUpdated

```solidity
event SlashCooldownUpdated(uint256 oldCooldown, uint256 newCooldown);
```

## Errors
### SlashCooldownActive

```solidity
error SlashCooldownActive(uint256 availableAt);
```

