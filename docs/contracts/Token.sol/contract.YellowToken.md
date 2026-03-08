# YellowToken
[Git Source](https://github.com/layer-3/yellow/blob/081e9e5ab0ebd446958aa9ad2a2b9aa91b26a69c/src/Token.sol)

**Inherits:**
ERC20Permit

Yellow Network utility token. ERC20 with permit functionality.
Fixed 10 billion supply minted entirely to the treasury at deployment.


## State Variables
### SUPPLY_CAP

```solidity
uint256 public constant SUPPLY_CAP = 10_000_000_000 ether
```


## Functions
### constructor


```solidity
constructor(address treasury) ERC20Permit("Yellow") ERC20("Yellow", "YELLOW");
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`treasury`|`address`|Address that receives the entire minted supply.|


## Errors
### InvalidAddress

```solidity
error InvalidAddress();
```

