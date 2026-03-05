# Yellow Network Documentation

## Table of Contents

### Introduction
- [What Is Yellow Network?](./what-is-yellow.md) — Plain-language guide for the general public

### Protocol
- [Overview](./protocol/overview.md) — Architecture, contracts, and how they fit together
- [Protocol Parameter Administration](./protocol/governance.md) — On-chain parameter updates by active node operators
- [Collateral](./protocol/staking.md) — Lock/unlock state machine for NodeRegistry and AppRegistry
- [Slashing](./protocol/slashing.md) — Adjudicator slashing and cooldown mechanism
- [Treasury](./protocol/treasury.md) — Foundation asset management

### Contract API Reference
Auto-generated from NatSpec via `forge doc`.

- [YellowToken](./contracts/Token.sol/contract.YellowToken.md)
- [Locker](./contracts/Locker.sol/abstract.Locker.md) (abstract base)
- [NodeRegistry](./contracts/NodeRegistry.sol/contract.NodeRegistry.md)
- [AppRegistry](./contracts/AppRegistry.sol/contract.AppRegistry.md)
- [YellowGovernor](./contracts/Governor.sol/contract.YellowGovernor.md)
- [Treasury](./contracts/Treasury.sol/contract.Treasury.md)
- [Faucet](./contracts/Faucet.sol/contract.Faucet.md)
- Interfaces
  - [ILock](./contracts/interfaces/ILock.sol/interface.ILock.md)
  - [ISlash](./contracts/interfaces/ISlash.sol/interface.ISlash.md)

### SDK
- [Getting Started](./sdk/getting-started.md) — Install, import, and use the SDK
- [API Reference](./sdk/api-reference.md) — All exports: ABIs, addresses, and types
- [Examples](./sdk/examples.md) — Code samples for viem, ethers, and wagmi

### Integration
- [UI Specification](./integration/ui-spec.md) — Frontend implementation guide
- [Events](./integration/events.md) — Contract events for real-time subscriptions
- [Deployment](./integration/deployment.md) — Deploying contracts and addresses

### Operations
- [Deployed Addresses](./operations/addresses.md) — Mainnet and Sepolia contract addresses

### Reference
- [FAQ](./FAQ.md) — Frequently asked questions
