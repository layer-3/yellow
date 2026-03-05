#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────
# Yellow Faucet Deployment Script (testnet only)
# Loads variables from .env — see .env.example for reference.
# ──────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_DIR}/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing .env file. Copy the example and fill in values:"
  echo "  cp .env.example .env"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

# ──────────────────────────────────────────────────────────────────────

if [ -z "${TOKEN_ADDRESS:-}" ]; then
  echo "TOKEN_ADDRESS is not set in .env"
  exit 1
fi

case "$NETWORK" in
  sepolia)  RPC_URL="$SEPOLIA_RPC_URL" ;;
  mainnet)  echo "Faucet is for testnet only."; exit 1 ;;
  *)        echo "Unknown network: $NETWORK"; exit 1 ;;
esac

FORGE_COMMON=(
  --rpc-url "$RPC_URL"
  --mnemonics "$MNEMONIC"
  --mnemonic-indexes 0
  --broadcast
  --verify
  --etherscan-api-key "$ETHERSCAN_API_KEY"
  -vvvv
)

echo "Deploying Faucet on $NETWORK ..."
forge script script/DeployFaucet.s.sol "${FORGE_COMMON[@]}"
echo "Done."
