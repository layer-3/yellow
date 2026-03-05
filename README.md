# Yellow Network

Smart contracts for the Yellow Network. Node operators post YELLOW tokens as a mandatory functional security deposit in the NodeRegistry to operate clearnode infrastructure. App builders post YELLOW in the AppRegistry as a service quality guarantee. The Treasury is managed directly by the Layer-3 Foundation.

## Architecture

```
Node operators post YELLOW --> NodeRegistry (IVotes) --> YellowGovernor --> TimelockController
                                collateral weight          proposals         delayed execution

App builders post YELLOW ----> AppRegistry (ISlash)
                                collateral + slashing

Foundation ------------------> Treasury
                                Foundation assets
```

## Contracts

### YellowToken

ERC-20 utility token with [EIP-2612](https://eips.ethereum.org/EIPS/eip-2612) permit support. Fixed supply of 10 billion YELLOW minted entirely to a treasury address at deployment. No mint or burn functions.

### NodeRegistry

Node operator registry. Operators post YELLOW tokens as a mandatory functional security deposit and receive collateral weight via the OpenZeppelin `Votes` interface (`IVotes`). Locked balances serve as collateral weight for protocol parameter administration with on-chain checkpointing.

**State machine per user:**

```
        lock(amount)            unlock()             withdraw()
  Idle ----------------> Locked ----------------> Unlocking ----------------> Idle
                            |                        |
                      lock(amount) top-up        relock()
                         (stays Locked)       (returns to Locked)
```

- `lock(amount)` -- deposit tokens into the vault. Can top up while Locked.
- `unlock()` -- start the withdrawal countdown (configurable at deployment). Collateral weight is removed.
- `withdraw()` -- after the unlock period elapses, claim the full balance.
- `relock()` -- cancel an in-progress unlock and restore collateral weight.
- `delegate(address)` -- delegate collateral weight. Users must call `delegate(self)` to activate their own weight.

### AppRegistry

Registry for app builders who post YELLOW as a service quality guarantee. Implements the same lock/unlock/withdraw state machine as NodeRegistry but without collateral weight. An adjudicator can slash a participant's balance in both Locked and Unlocking states as penalty for misbehaviour.

- `slash(user, amount, recipient, decision)` -- callable only by an address with `ADJUDICATOR_ROLE`. Reduces the user's balance and transfers slashed tokens to the recipient.
- Full slash resets the user's state to Idle.
- **Slash cooldown** -- a global cooldown can be set by the admin (`DEFAULT_ADMIN_ROLE`) via `setSlashCooldown(seconds)` to rate-limit slashing. This prevents a rogue adjudicator from batch-draining all users in a single transaction, giving the admin time to revoke the role. Set to `0` to disable (default).

### YellowGovernor

OpenZeppelin Governor for protocol parameter administration with the following extensions:

| Extension | Purpose |
|---|---|
| GovernorSettings | Configurable consensus delay, period, and proposal threshold |
| GovernorCountingSimple | For / Against / Abstain signalling |
| GovernorVotes | Reads collateral weight from the NodeRegistry |
| GovernorVotesQuorumFraction | Quorum as percentage of total locked supply |
| GovernorTimelockControl | Routes execution through TimelockController |

**Proposal lifecycle:** Propose --> Signal (after consensus delay) --> Queue (if passed) --> Execute (after timelock delay)

### TimelockController

OpenZeppelin TimelockController. Enforces a delay between proposal approval and execution, giving participants time to react. The Governor holds the proposer and canceller roles. Execution is open (anyone can trigger after the delay).

### Treasury

Secure vault for Layer-3 Foundation assets, supporting ETH and ERC-20 transfers. Owned directly by the Foundation address via `Ownable2Step`.

- `transfer(token, to, amount)` -- moves funds out of the treasury. Use `address(0)` for ETH.

## SDK

The [`@yellow-org/contracts`](https://www.npmjs.com/package/@yellow-org/contracts) npm package exports typed ABIs and deployed addresses for use with viem, ethers.js, and wagmi. See [`sdk/README.md`](sdk/README.md) for usage.

```bash
npm install @yellow-org/contracts
```

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Bun](https://bun.sh) (for SDK and docs scripts)

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

### Mainnet

| Contract | Address |
|---|---|
| YellowToken | `0x236eB848C95b231299B4AA9f56c73D6893462720` |

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
| `DeployRegistry.s.sol` | — | Deploy registries + parameter administration |

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

### Post-Deployment

After deploying, rebuild the SDK and docs to pick up new addresses from broadcast artifacts:

```bash
make sdk-build   # extracts ABIs + addresses
make docs        # regenerates docs (including address tables)
```

## Release

```bash
make release v=1.1.0
git push origin master --tags
cd sdk && npm publish
```

## License

MIT (contracts) / GPL-3.0-or-later (YellowToken)
