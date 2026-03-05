# NodeRegistry
[Git Source](https://github.com/layer-3/yellow/blob/b67bbac4d4ae41afab3ea9edfcd53990dc2741dd/src/NodeRegistry.sol)

**Inherits:**
[Locker](/src/Locker.sol/abstract.Locker.md), Votes

**Title:**
NodeRegistry

Node operator registry with governance voting. Operators lock YELLOW
tokens to register and gain voting power in the Yellow Network DAO.
Extends OZ Votes to act as the voting-power source for governance.
Auto-self-delegates on first lock so voting power is immediately active.

Voting units are granted on lock and removed on unlock/relock via hooks.


## Functions
### constructor


```solidity
constructor(address asset_, uint256 unlockPeriod_) Locker(asset_, unlockPeriod_) EIP712(NAME, VERSION);
```

### _afterLock


```solidity
function _afterLock(address target, uint256 amount) internal override;
```

### _afterUnlock


```solidity
function _afterUnlock(address account, uint256 balance) internal override;
```

### _afterRelock


```solidity
function _afterRelock(address account, uint256 balance) internal override;
```

### _getVotingUnits

Returns the locked balance as voting units for the Votes system.


```solidity
function _getVotingUnits(address account) internal view override returns (uint256);
```

