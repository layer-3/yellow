# Deployment

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- An `.env` file (see `.env.example`)

## Scripts

| Script | Wrapper | Purpose |
|---|---|---|
| `DeployToken.s.sol` | `deploy-token.sh` | Deploy YellowToken |
| `DeployFaucet.s.sol` | `deploy-faucet.sh` | Deploy Faucet (testnet only) |
| `DeployTreasury.s.sol` | — | Deploy Treasury |
| `DeployRegistry.s.sol` | — | Deploy registries + governance |

## Deployment Order

1. **YellowToken** — deploy first, get the token address
2. **Registry + Governance** — needs token address; deploys NodeRegistry, AppRegistry, TimelockController, YellowGovernor in one script
3. **Treasury** — independent; can be owned by Foundation or transferred to TimelockController

## Configuration

```bash
cp .env.example .env
```

### Token

| Variable | Description |
|---|---|
| `FOUNDATION_ADDRESS` | Receives the initial 10B YELLOW supply |

### Registry + Governance

| Variable | Default | Description |
|---|---|---|
| `TOKEN_ADDRESS` | — | Deployed YellowToken address |
| `ADJUDICATOR_ADDRESS` | — | Initial adjudicator for AppRegistry |
| `PROPOSAL_GUARDIAN` | — | Foundation multisig for emergency cancel |
| `VOTING_DELAY` | 7200 | Blocks before voting starts (~1 day) |
| `VOTING_PERIOD` | 50400 | Blocks vote stays open (~1 week) |
| `PROPOSAL_THRESHOLD` | 10M YELLOW | Min voting power to propose |
| `QUORUM_NUMERATOR` | 4 | Quorum as % of locked supply |
| `QUORUM_FLOOR` | 100M YELLOW | Minimum absolute quorum |
| `VOTE_EXTENSION` | 14400 | Late quorum extension (~2 days) |
| `NODE_UNLOCK_PERIOD` | 14 days | NodeRegistry withdrawal delay |
| `APP_UNLOCK_PERIOD` | 14 days | AppRegistry withdrawal delay |
| `TIMELOCK_DELAY` | 172800 | Seconds before execution (2 days) |

### Treasury

| Variable | Default | Description |
|---|---|---|
| `FOUNDATION_ADDRESS` | — | Treasury owner |
| `TREASURY_NAME` | "Treasury" | Human-readable label |

### Faucet (Sepolia only)

| Variable | Default | Description |
|---|---|---|
| `TOKEN_ADDRESS` | — | Deployed YellowToken address |
| `DRIP_AMOUNT` | 1000 YELLOW | Amount per drip |
| `DRIP_COOLDOWN` | 86400 (1 day) | Seconds between drips |

## Running

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

For registry and treasury, run forge directly:

```bash
forge script script/DeployRegistry.s.sol --rpc-url $RPC --broadcast --verify
forge script script/DeployTreasury.s.sol --rpc-url $RPC --broadcast --verify
```

## Post-Deployment

After deploying the registry + governance stack, the script automatically:

1. Grants `ADJUDICATOR_ROLE` to the specified adjudicator
2. Transfers AppRegistry `DEFAULT_ADMIN_ROLE` to the TimelockController
3. Renounces the deployer's admin roles on both AppRegistry and TimelockController

No manual role setup is needed.

## Updating the SDK

After deploying new contracts, update `sdk/src/addresses.ts` with the new addresses and publish a new SDK version:

```bash
git tag v0.2.0
git push origin v0.2.0
```

The CI pipeline will build and publish automatically.
