# Governance

The Yellow Network DAO is governed by YELLOW token holders who lock tokens in the NodeRegistry. Governance follows a propose-vote-queue-execute lifecycle with a timelock delay.

## Voting Power

Node operators lock YELLOW tokens into the **NodeRegistry**, which extends OpenZeppelin's `Votes`. Locking tokens grants voting power 1:1.

- **Auto-self-delegation** — on first lock, the user is automatically delegated to themselves so voting power is immediately active
- **Unlock removes votes** — calling `unlock()` zeroes out voting power immediately, even before the unlock period elapses
- **Relock restores votes** — cancelling an unlock via `relock()` gives back full voting power
- **Delegation** — users can delegate voting power to any address via `delegate(address)`

## Proposal Lifecycle

```
Propose ──► [voting delay] ──► Vote ──► [voting period] ──► Queue ──► [timelock delay] ──► Execute
```

### States

| State | Value | Description |
|---|---|---|
| Pending | 0 | Proposal created, waiting for voting delay |
| Active | 1 | Voting is open |
| Canceled | 2 | Proposal was canceled |
| Defeated | 3 | Vote failed (quorum not met or more Against) |
| Succeeded | 4 | Vote passed, ready to queue |
| Queued | 5 | In timelock, waiting for delay |
| Expired | 6 | Queued but not executed in time |
| Executed | 7 | Successfully executed |

## Governor Extensions

| Extension | Purpose |
|---|---|
| `GovernorSettings` | Configurable voting delay, period, and proposal threshold |
| `GovernorCountingSimple` | For / Against / Abstain voting |
| `GovernorVotes` | Reads voting power from the NodeRegistry |
| `GovernorVotesQuorumFraction` | Quorum as percentage of total locked supply |
| `GovernorTimelockControl` | Routes execution through TimelockController |
| `GovernorPreventLateQuorum` | Extends deadline if quorum reached late |
| `GovernorProposalGuardian` | Foundation emergency cancel |

## Quorum

Quorum is calculated as `max(fractionalQuorum, quorumFloor)`:

- **Fractional quorum** — percentage of total locked supply (default 4%)
- **Quorum floor** — absolute minimum (default 100M YELLOW) so quorum doesn't collapse if most tokens unlock

The quorum floor is checkpointed and can be updated via governance (`setQuorumFloor`).

## Default Parameters

| Parameter | Default | Description |
|---|---|---|
| Voting delay | 7,200 blocks (~1 day) | Time before voting starts |
| Voting period | 50,400 blocks (~1 week) | How long voting stays open |
| Proposal threshold | 10,000,000 YELLOW | Minimum voting power to create a proposal |
| Quorum numerator | 4% | Percentage of locked supply required |
| Quorum floor | 100,000,000 YELLOW | Absolute minimum quorum |
| Vote extension | 14,400 blocks (~2 days) | Extended deadline on late quorum |
| Timelock delay | 172,800 seconds (2 days) | Delay before execution |

## Access Control Flow

```
NodeRegistry (voting power) ──► YellowGovernor (proposals/votes) ──► TimelockController (delayed execution)
                                                                              │
                                                                   AppRegistry (admin role)
                                                                   Treasury (if owned by timelock)
```

The TimelockController is the actual executor — it holds `DEFAULT_ADMIN_ROLE` on the AppRegistry and can own Treasuries. The Governor is the only proposer/canceller on the timelock. After deployment, the deployer renounces all admin roles, leaving governance fully in control.

## Common Governance Actions

| Action | Target | Function |
|---|---|---|
| Transfer ETH from Treasury | Treasury | `transfer(address(0), recipient, amount)` |
| Transfer YELLOW from Treasury | Treasury | `transfer(tokenAddr, recipient, amount)` |
| Grant adjudicator role | AppRegistry | `grantRole(ADJUDICATOR_ROLE, address)` |
| Revoke adjudicator role | AppRegistry | `revokeRole(ADJUDICATOR_ROLE, address)` |
| Set slash cooldown | AppRegistry | `setSlashCooldown(seconds)` |
| Update quorum floor | Governor | `setQuorumFloor(newFloor)` |
| Update governance settings | Governor | `setVotingDelay`, `setVotingPeriod`, `setProposalThreshold` |
| Set/remove proposal guardian | Governor | `setProposalGuardian(address)` |
