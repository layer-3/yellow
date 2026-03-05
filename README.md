# Yellow Network

On-chain governance and registry system for the Yellow Network. Node operators lock YELLOW tokens in the NodeRegistry to gain voting power and govern the DAO. App owners lock collateral in the AppRegistry where an adjudicator can slash misbehaving participants. The Treasury is managed directly by the Layer-3 Foundation.

## Architecture

```
Node operators lock YELLOW --> NodeRegistry (IVotes) --> YellowGovernor --> TimelockController
                                voting power               proposals         delayed execution

App owners lock YELLOW -----> AppRegistry (ISlash)
                               collateral + slashing

Foundation -----------------> Treasury
                               Foundation assets
```

## Contracts

### YellowToken

ERC-20 utility token with [EIP-2612](https://eips.ethereum.org/EIPS/eip-2612) permit support. Fixed supply of 10 billion YELLOW minted entirely to a treasury address at deployment. No mint or burn functions.

### NodeRegistry

Node operator registry with governance voting. Operators lock YELLOW tokens and gain voting power via the OpenZeppelin `Votes` interface (`IVotes`). Locked balances serve as governance voting power with on-chain checkpointing.

**State machine per user:**

```
        lock(amount)            unlock()             withdraw()
  Idle ----------------> Locked ----------------> Unlocking ----------------> Idle
                            |                        |
                      lock(amount) top-up        relock()
                         (stays Locked)       (returns to Locked)
```

- `lock(amount)` -- deposit tokens into the vault. Can top up while Locked.
- `unlock()` -- start the withdrawal countdown (configurable at deployment). Voting power is removed.
- `withdraw()` -- after the unlock period elapses, claim the full balance.
- `relock()` -- cancel an in-progress unlock and restore voting power.
- `delegate(address)` -- delegate voting power. Users must call `delegate(self)` to activate their own votes.

### AppRegistry

Registry for app owners who lock YELLOW as collateral. Implements the same lock/unlock/withdraw state machine as NodeRegistry but without governance voting. An adjudicator can slash a participant's balance in both Locked and Unlocking states as penalty for misbehaviour.

- `slash(user, amount)` -- callable only by the adjudicator. Reduces the user's balance and transfers slashed tokens to the adjudicator.
- Full slash resets the user's state to Idle.

### YellowGovernor

OpenZeppelin Governor with the following extensions:

| Extension | Purpose |
|---|---|
| GovernorSettings | Configurable voting delay, period, and proposal threshold |
| GovernorCountingSimple | For / Against / Abstain voting |
| GovernorVotes | Reads voting power from the NodeRegistry |
| GovernorVotesQuorumFraction | Quorum as percentage of total locked supply |
| GovernorTimelockControl | Routes execution through TimelockController |

**Proposal lifecycle:** Propose --> Vote (after voting delay) --> Queue (if passed) --> Execute (after timelock delay)

### TimelockController

OpenZeppelin TimelockController. Enforces a delay between proposal approval and execution, giving stakeholders time to react. The Governor holds the proposer and canceller roles. Execution is open (anyone can trigger after the delay).

### Treasury

Secure vault for Layer-3 Foundation assets, supporting ETH and ERC-20 withdrawals. Owned directly by the Foundation address via `Ownable2Step`.

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Setup

```bash
git clone <repo-url>
cd yellow
forge install
```

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Format

```bash
forge fmt
```

## Deployed Addresses

### Sepolia

| Contract | Address |
|---|---|
| YellowToken | `0x236eB848C95b231299B4AA9f56c73D6893462720` |
| Faucet | `0x914abaDC0e36e03f29e4F1516951125c774dBAc8` |

## Deployment

Deployment is split into separate scripts, each with its own bash wrapper that loads configuration from `.env`:

| Script | Bash | Purpose |
|---|---|---|
| `DeployToken.s.sol` | `deploy-token.sh` | Deploy YellowToken |
| `DeployFaucet.s.sol` | `deploy-faucet.sh` | Deploy Faucet (testnet only) |
| `DeployTreasury.s.sol` | — | Deploy Treasury |
| `DeployRegistry.s.sol` | — | Deploy registries + governance |

### Configuration

```bash
cp .env.example .env
# Fill in values, then run the scripts
```

See `.env.example` for all available variables.

### Sepolia

```bash
./script/deploy-token.sh
./script/deploy-faucet.sh
```

### Mainnet

Set `NETWORK="mainnet"` in `.env`, then:

```bash
./script/deploy-token.sh
```

## License

MIT (contracts) / GPL-3.0-or-later (YellowToken)
