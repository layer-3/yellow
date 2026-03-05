# Protocol Overview

Yellow Network is an on-chain governance and registry system. Node operators lock YELLOW tokens to gain voting power and govern the DAO. App owners lock collateral where adjudicators can slash misbehaving participants. The Treasury holds Foundation assets.

## Architecture

```
Node operators lock YELLOW ──► NodeRegistry (IVotes) ──► YellowGovernor ──► TimelockController
                                 voting power               proposals         delayed execution
                                                                                    │
App owners lock YELLOW ────────► AppRegistry (ISlash)  ◄────────────────────────────┘
                                  collateral + slashing       (admin role)

Foundation ────────────────────► Treasury  ◄────────────────────────────────────────┘
                                  Foundation assets            (ownership)
```

## Contracts

| Contract | Purpose | Key Interface |
|---|---|---|
| **YellowToken** | ERC-20 utility token, fixed 10B supply, EIP-2612 permit | `IERC20`, `IERC20Permit` |
| **Locker** | Abstract single-asset vault with time-locked withdrawals | `ILock` |
| **NodeRegistry** | Node operator staking with governance voting power | `ILock`, `IVotes` |
| **AppRegistry** | App owner collateral with adjudicator slashing | `ILock`, `ISlash`, `AccessControl` |
| **YellowGovernor** | DAO governance: proposals, voting, quorum | `IGovernor` |
| **TimelockController** | Delayed execution of governance actions | OZ `TimelockController` |
| **Treasury** | Foundation vault for ETH and ERC-20 assets | `Ownable2Step` |
| **Faucet** | Testnet token dispenser (Sepolia only) | — |

## Token Economics

- **Fixed supply:** 10,000,000,000 YELLOW (10 billion)
- **No mint/burn:** supply is fixed at deployment
- **Permit:** EIP-2612 gasless approvals

## Access Control Summary

| Role | Held By | Can Do |
|---|---|---|
| NodeRegistry — no roles | Open | Anyone can lock/unlock/delegate |
| AppRegistry `DEFAULT_ADMIN_ROLE` | TimelockController (governance) | Grant/revoke adjudicators, set slash cooldown |
| AppRegistry `ADJUDICATOR_ROLE` | Adjudicator address(es) | Slash misbehaving users |
| Governor proposer | Anyone with sufficient voting power | Create proposals |
| Governor proposal guardian | Foundation multisig | Cancel any proposal (emergency) |
| TimelockController executor | Open (anyone) | Execute queued proposals after delay |
| Treasury owner | Foundation or TimelockController | Transfer funds out |

## Security Model

- **Timelock delay** — all governance actions are delayed (default 2 days), giving stakeholders time to exit
- **Quorum floor** — absolute minimum quorum prevents governance capture when total locked supply is low
- **Late quorum protection** — voting deadline extends if quorum is reached late, preventing last-second whale attacks
- **Proposal guardian** — Foundation can emergency-cancel proposals; removable via governance
- **Slash cooldown** — rate-limits slashing to prevent batch-draining by a rogue adjudicator
- **Unlock period** — 14-day withdrawal delay prevents flash-loan governance attacks
- **Ownable2Step** — Treasury ownership transfer requires explicit acceptance
