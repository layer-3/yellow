# Yellow Network

On-chain governance system for the Yellow Network DAO. Token holders lock YELLOW tokens to gain voting power and govern the DAO treasury through proposals.

## Architecture

```
Users lock YELLOW --> Locker (IVotes) --> YellowGovernor --> TimelockController --> Treasury
                      voting power         proposals         delayed execution      DAO assets
```

## Contracts

### YellowToken

ERC-20 utility token with [EIP-2612](https://eips.ethereum.org/EIPS/eip-2612) permit support. Fixed supply of 10 billion YELLOW minted entirely to a treasury address at deployment. No mint or burn functions.

### Locker

Single-asset vault where users lock YELLOW tokens. Implements the OpenZeppelin `Votes` interface (`IVotes`) so locked balances serve as governance voting power with on-chain checkpointing.

**State machine per user:**

```
        lock(amount)            unlock()             withdraw()
  Idle ----------------> Locked ----------------> Unlocking ----------------> Idle
                            |
                      lock(amount) top-up
                         (stays Locked)
```

- `lock(amount)` -- deposit tokens into the vault. Can top up while Locked.
- `unlock()` -- start the withdrawal countdown (configurable at deployment). Voting power is removed.
- `withdraw()` -- after the unlock period elapses, claim the full balance.
- `delegate(address)` -- delegate voting power. Users must call `delegate(self)` to activate their own votes.

### YellowGovernor

OpenZeppelin Governor with the following extensions:

| Extension | Purpose |
|---|---|
| GovernorSettings | Configurable voting delay, period, and proposal threshold |
| GovernorCountingSimple | For / Against / Abstain voting |
| GovernorVotes | Reads voting power from the Locker |
| GovernorVotesQuorumFraction | Quorum as percentage of total locked supply |
| GovernorTimelockControl | Routes execution through TimelockController |

**Proposal lifecycle:** Propose --> Vote (after voting delay) --> Queue (if passed) --> Execute (after timelock delay)

### TimelockController

OpenZeppelin TimelockController. Enforces a delay between proposal approval and execution, giving stakeholders time to react. The Governor holds the proposer and canceller roles. Execution is open (anyone can trigger after the delay).

### Treasury

DAO asset vault supporting ETH and ERC-20 withdrawals. Owned by the TimelockController via `Ownable2Step`, so all fund movements require a governance vote.

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

The deployment script deploys all five contracts and wires them together in a single transaction.

### Configuration

| Environment Variable | Default | Description |
|---|---|---|
| `TREASURY_ADDRESS` | **(required)** | Address receiving the initial YELLOW supply |
| `VOTING_DELAY` | `7200` (~1 day) | Blocks before voting starts after proposal |
| `VOTING_PERIOD` | `50400` (~1 week) | Blocks the voting window stays open |
| `PROPOSAL_THRESHOLD` | `10000000000000000000000000` (10M YELLOW) | Minimum voting power to create a proposal |
| `QUORUM_NUMERATOR` | `4` | Quorum as percentage of total locked supply |
| `QUORUM_FLOOR` | `100000000000000000000000000` (100M YELLOW) | Minimum absolute quorum in tokens |
| `UNLOCK_PERIOD` | `1209600` (14 days) | Locker withdrawal waiting period in seconds |
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
  forge script script/Deploy.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

The private key above is Anvil's default account #0. Replace `TREASURY_ADDRESS` with whichever Anvil account should receive the token supply.

### Mainnet

```bash
TREASURY_ADDRESS=<multisig-or-dao-address> \
  forge script script/Deploy.s.sol \
  --rpc-url $ETH_RPC_URL \
  --ledger \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

Replace `--ledger` with `--private-key` or `--trezor` depending on your signer. Add `--slow` if the RPC rate-limits.

### Post-deployment

After deployment, the Treasury ownership transfer is **pending** in the TimelockController. Once the timelock delay elapses (default 2 days), finalize it:

```bash
cast send <TIMELOCK_ADDRESS> \
  "execute(address,uint256,bytes,bytes32,bytes32)" \
  <TREASURY_ADDRESS> 0 \
  $(cast calldata "acceptOwnership()") \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  --rpc-url $ETH_RPC_URL \
  --private-key <ANY_ACCOUNT>
```

Verify the transfer completed:

```bash
cast call <TREASURY_ADDRESS> "owner()(address)" --rpc-url $ETH_RPC_URL
# Should return the TimelockController address
```

## License

MIT (contracts) / GPL-3.0-or-later (YellowToken)
