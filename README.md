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

## Deployment

The deployment script deploys all contracts and wires them together in a single transaction.

### Configuration

| Environment Variable | Default | Description |
|---|---|---|
| `TREASURY_ADDRESS` | **(required)** | Address receiving the initial YELLOW supply |
| `FOUNDATION_ADDRESS` | **(required)** | Address that owns the Treasury directly |
| `ADJUDICATOR_ADDRESS` | **(required)** | Address authorised to slash in AppRegistry |
| `VOTING_DELAY` | `7200` (~1 day) | Blocks before voting starts after proposal |
| `VOTING_PERIOD` | `50400` (~1 week) | Blocks the voting window stays open |
| `PROPOSAL_THRESHOLD` | `10000000000000000000000000` (10M YELLOW) | Minimum voting power to create a proposal |
| `QUORUM_NUMERATOR` | `4` | Quorum as percentage of total locked supply |
| `QUORUM_FLOOR` | `100000000000000000000000000` (100M YELLOW) | Minimum absolute quorum in tokens |
| `NODE_UNLOCK_PERIOD` | `1209600` (14 days) | NodeRegistry withdrawal waiting period in seconds |
| `APP_UNLOCK_PERIOD` | `1209600` (14 days) | AppRegistry withdrawal waiting period in seconds |
| `TIMELOCK_DELAY` | `172800` (2 days) | Seconds before a passed proposal can execute |

Block estimates assume 12-second block times (Ethereum mainnet).

### Local (Anvil)

Start a local node:

```bash
anvil
```

In a second terminal, deploy:

```bash
TREASURY_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
FOUNDATION_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
ADJUDICATOR_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 \
  forge script script/Deploy.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

The private key above is Anvil's default account #0. Replace addresses with whichever Anvil accounts should receive the token supply, own the treasury, and serve as adjudicator.

### Mainnet

```bash
TREASURY_ADDRESS=<multisig-or-dao-address> \
FOUNDATION_ADDRESS=<foundation-multisig> \
ADJUDICATOR_ADDRESS=<adjudicator-address> \
  forge script script/Deploy.s.sol \
  --rpc-url $ETH_RPC_URL \
  --ledger \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

Replace `--ledger` with `--private-key` or `--trezor` depending on your signer. Add `--slow` if the RPC rate-limits.

## License

MIT (contracts) / GPL-3.0-or-later (YellowToken)
