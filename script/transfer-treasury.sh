#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────
# Treasury Transfer — Gnosis Safe Calldata Generator
#
# Encodes a Treasury.transfer(token, to, amount) call and prints the
# calldata to paste into Gnosis Safe → Transaction Builder.
#
# Loads variables from .env — see .env.example for reference.
#
# Required .env variables:
#   TREASURY_ADDRESS — address of the Treasury contract
#   TOKEN_ADDRESS    — ERC-20 address, or 0x0000000000000000000000000000000000000000 for ETH
#   RECIPIENT        — destination address
#   AMOUNT           — amount in whole YELLOW tokens (18 decimals applied)
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

AMOUNT_WEI=$(cast --to-wei "$AMOUNT")
CALLDATA=$(cast calldata "transfer(address,address,uint256)" "$TOKEN_ADDRESS" "$RECIPIENT" "$AMOUNT_WEI")

echo "=== Gnosis Safe Transaction ==="
echo "To:       $TREASURY_ADDRESS"
echo "Value:    0"
echo "Calldata: $CALLDATA"
echo ""
echo "--- Decoded ---"
echo "Token:     $TOKEN_ADDRESS"
echo "Recipient: $RECIPIENT"
echo "Amount:    $AMOUNT YELLOW ($AMOUNT_WEI wei)"
