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

| Contract | Address | Note |
|---|---|---|
| YellowToken | `0x236eB848C95b231299B4AA9f56c73D6893462720` | |
| Treasury | `0x914abaDC0e36e03f29e4F1516951125c774dBAc8` | Founder |
| Treasury | `0xAec5157545635A7523EFB5ABe3a37F52dB7DE72e` | Community |
| Treasury | `0xd572f3a0967856a09054578439aCe81B2f2ff88B` | Token Sale |
| Treasury | `0xfD8E336757aE9cDc0766264064B51492814fCd47` | Foundation |
| Treasury | `0xE277830b3444EA2cfee2B95F780c971222DEcfA9` | Network |
| Treasury | `0xA8f52FFe4DeE9565505f8E390163A335D6A2F708` | Liquidity |
| NodeRegistry | `0xB0C7aA4ca9ffF4A48B184d8425eb5B6Fa772d820` | |
| AppRegistry | `0x5A70029B843eE272A2392acE21DA392693eef1c6` | |
| TimelockController | `0x9530896F9622b925c37dF5Cfa271cc9deBB226b7` | |
| YellowGovernor | `0x7Ce0AE21E11dFEDA2F6e4D8bF2749E4061119512` | |

### Sepolia

| Contract | Address | Note |
|---|---|---|
| YellowToken | `0x236eB848C95b231299B4AA9f56c73D6893462720` | |
| Faucet | `0x914abaDC0e36e03f29e4F1516951125c774dBAc8` | |
| Treasury | `0x6f4eeD96cA1388803A9923476a0F5e19703d1e7C` | Founder |
| Treasury | `0x3939a80FE4cc2F16F1294a995A4255B68d8c1F27` | Community |
| Treasury | `0x9b4742c0aEFfE3DD16c924f4630F6964fe1ad420` | Token Sale |
| Treasury | `0xbb5006195974B1d3c36e46EA2D7665FE1e65ADf2` | Foundation |
| Treasury | `0x72F4461A79AB44BbCf1E70c1e3CE9a5a2C2e1920` | Network |
| Treasury | `0x5825BD45C3f495391f4a7690be581b1c91Ac6959` | Liquidity |

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
