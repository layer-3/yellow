#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Yellow Governance Stack — Integration Test
#
# Spins up a local Anvil chain and exercises the full deployment +
# governance lifecycle end-to-end using only cast/forge CLI tools.
#
# Usage:  ./script/integration-test.sh
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Helpers ──────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

pass() { echo -e "  ${GREEN}✓ $1${NC}"; }
fail() { echo -e "  ${RED}✗ $1${NC}"; exit 1; }
step() { echo -e "\n${CYAN}▸ $1${NC}"; }

assert_eq() {
    local actual="$1" expected="$2" msg="$3"
    if [[ "$actual" != "$expected" ]]; then
        fail "$msg (expected $expected, got $actual)"
    fi
    pass "$msg"
}

# Strip trailing annotations cast sometimes appends (e.g. " [1e28]")
call() { cast call "$@" --rpc-url "$RPC" | awk '{print $1}'; }
send() { cast send "$@" --rpc-url "$RPC" > /dev/null; }
mine() { cast rpc anvil_mine "$1" --rpc-url "$RPC" > /dev/null; }
warp() { cast rpc anvil_increaseTime "$1" --rpc-url "$RPC" > /dev/null; }

# ── Pre-flight checks ───────────────────────────────────────────
[[ -f "foundry.toml" ]] || { echo "Run from project root."; exit 1; }
command -v anvil &>/dev/null || { echo "anvil not found."; exit 1; }
command -v forge &>/dev/null || { echo "forge not found."; exit 1; }

# ── Anvil accounts ───────────────────────────────────────────────
DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
DEPLOYER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ALICE=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
ALICE_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
BOB=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
BOB_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a

RPC=http://127.0.0.1:8545
ZERO_HASH=0x0000000000000000000000000000000000000000000000000000000000000000
ADDR_ZERO=0x0000000000000000000000000000000000000000

# ── Cleanup on exit ──────────────────────────────────────────────
cleanup() { [[ -n "${ANVIL_PID:-}" ]] && kill "$ANVIL_PID" 2>/dev/null; wait "$ANVIL_PID" 2>/dev/null || true; }
trap cleanup EXIT

# ═════════════════════════════════════════════════════════════════
#  1. Start Anvil
# ═════════════════════════════════════════════════════════════════
step "Starting Anvil"
anvil > /dev/null 2>&1 &
ANVIL_PID=$!
sleep 2
cast block-number --rpc-url "$RPC" > /dev/null 2>&1 || fail "Anvil failed to start"
pass "Anvil running (PID $ANVIL_PID)"

# ═════════════════════════════════════════════════════════════════
#  2. Deploy governance stack
# ═════════════════════════════════════════════════════════════════
step "Deploying governance stack"

DEPLOY_OUTPUT=$(TREASURY_ADDRESS=$DEPLOYER \
  VOTING_DELAY=1 \
  VOTING_PERIOD=10 \
  PROPOSAL_THRESHOLD=0 \
  QUORUM_NUMERATOR=4 \
  QUORUM_FLOOR=0 \
  TIMELOCK_DELAY=1 \
  forge script script/Deploy.s.sol \
    --rpc-url "$RPC" \
    --broadcast \
    --private-key "$DEPLOYER_PK" 2>&1)

TOKEN=$(echo "$DEPLOY_OUTPUT"    | grep "YellowToken:"         | awk '{print $NF}')
LOCKER=$(echo "$DEPLOY_OUTPUT"   | grep "Locker:"              | awk '{print $NF}')
TIMELOCK=$(echo "$DEPLOY_OUTPUT" | grep "TimelockController:"  | awk '{print $NF}')
GOVERNOR=$(echo "$DEPLOY_OUTPUT" | grep "YellowGovernor:"      | awk '{print $NF}')
TREASURY=$(echo "$DEPLOY_OUTPUT" | grep "Treasury:"            | awk '{print $NF}')

for name in TOKEN LOCKER TIMELOCK GOVERNOR TREASURY; do
    [[ -n "${!name}" ]] || fail "Could not parse $name address from deploy output"
done

echo "  Token:     $TOKEN"
echo "  Locker:    $LOCKER"
echo "  Timelock:  $TIMELOCK"
echo "  Governor:  $GOVERNOR"
echo "  Treasury:  $TREASURY"
pass "Deployment complete"

# ═════════════════════════════════════════════════════════════════
#  3. Complete Treasury ownership transfer via Timelock
# ═════════════════════════════════════════════════════════════════
step "Completing Treasury ownership transfer"

warp 2; mine 1

ACCEPT_DATA=$(cast calldata "acceptOwnership()")
send "$TIMELOCK" \
    "execute(address,uint256,bytes,bytes32,bytes32)" \
    "$TREASURY" 0 "$ACCEPT_DATA" "$ZERO_HASH" "$ZERO_HASH" \
    --private-key "$DEPLOYER_PK"

OWNER=$(call "$TREASURY" "owner()(address)")
assert_eq "$OWNER" "$TIMELOCK" "Treasury owned by Timelock"

# ═════════════════════════════════════════════════════════════════
#  4. Token sanity checks
# ═════════════════════════════════════════════════════════════════
step "Verifying token"

SUPPLY=$(call "$TOKEN" "totalSupply()(uint256)")
assert_eq "$SUPPLY" "10000000000000000000000000000" "Total supply = 10 B"

DEPLOYER_BAL=$(call "$TOKEN" "balanceOf(address)(uint256)" "$DEPLOYER")
assert_eq "$DEPLOYER_BAL" "$SUPPLY" "Deployer holds full supply"

NAME=$(call "$TOKEN" "name()(string)" | tr -d '"')
assert_eq "$NAME" "Yellow" "Token name"

SYMBOL=$(call "$TOKEN" "symbol()(string)" | tr -d '"')
assert_eq "$SYMBOL" "YELLOW" "Token symbol"

# ═════════════════════════════════════════════════════════════════
#  5. Fund Treasury (ETH + YELLOW)
# ═════════════════════════════════════════════════════════════════
step "Funding Treasury"

send "$TREASURY" --value 10ether --private-key "$DEPLOYER_PK"
ETH_BAL=$(cast balance "$TREASURY" --rpc-url "$RPC")
assert_eq "$ETH_BAL" "10000000000000000000" "Treasury holds 10 ETH"

MILLION="1000000000000000000000000"   # 1 M * 1e18
send "$TOKEN" "transfer(address,uint256)" "$TREASURY" "$MILLION" --private-key "$DEPLOYER_PK"
T_BAL=$(call "$TOKEN" "balanceOf(address)(uint256)" "$TREASURY")
assert_eq "$T_BAL" "$MILLION" "Treasury holds 1 M YELLOW"

# ═════════════════════════════════════════════════════════════════
#  6. Locker — lock & delegate
# ═════════════════════════════════════════════════════════════════
step "Locker: lock + delegate"

ALICE_FUND="500000000000000000000000000"   # 500 M
LOCK_AMT="200000000000000000000000000"     # 200 M

send "$TOKEN" "transfer(address,uint256)" "$ALICE" "$ALICE_FUND" --private-key "$DEPLOYER_PK"
send "$TOKEN" "approve(address,uint256)" "$LOCKER" "$LOCK_AMT"   --private-key "$ALICE_PK"
send "$LOCKER" "lock(uint256)" "$LOCK_AMT"                       --private-key "$ALICE_PK"

assert_eq "$(call "$LOCKER" "balanceOf(address)(uint256)" "$ALICE")" "$LOCK_AMT" "Alice locked 200 M"
assert_eq "$(call "$LOCKER" "lockStateOf(address)(uint8)" "$ALICE")" "1"         "Alice state = Locked"

send "$LOCKER" "delegate(address)" "$ALICE" --private-key "$ALICE_PK"
mine 1

assert_eq "$(call "$LOCKER" "getVotes(address)(uint256)" "$ALICE")" "$LOCK_AMT" "Alice voting power = 200 M"

# ═════════════════════════════════════════════════════════════════
#  7. Locker — unlock → relock round-trip
# ═════════════════════════════════════════════════════════════════
step "Locker: unlock → relock"

send "$LOCKER" "unlock()" --private-key "$ALICE_PK"
assert_eq "$(call "$LOCKER" "lockStateOf(address)(uint8)" "$ALICE")"  "2" "State = Unlocking"
assert_eq "$(call "$LOCKER" "getVotes(address)(uint256)" "$ALICE")"   "0" "Votes dropped to 0"

send "$LOCKER" "relock()" --private-key "$ALICE_PK"
assert_eq "$(call "$LOCKER" "lockStateOf(address)(uint8)" "$ALICE")"  "1"         "State = Locked"
assert_eq "$(call "$LOCKER" "getVotes(address)(uint256)" "$ALICE")"   "$LOCK_AMT" "Votes restored"

# ═════════════════════════════════════════════════════════════════
#  8. Locker — full unlock → withdraw (Bob)
# ═════════════════════════════════════════════════════════════════
step "Locker: lock → unlock → wait 14 d → withdraw (Bob)"

BOB_AMT="100000000000000000000000000"  # 100 M

send "$TOKEN"  "transfer(address,uint256)" "$BOB" "$BOB_AMT"    --private-key "$DEPLOYER_PK"
send "$TOKEN"  "approve(address,uint256)" "$LOCKER" "$BOB_AMT"  --private-key "$BOB_PK"
send "$LOCKER" "lock(uint256)" "$BOB_AMT"                       --private-key "$BOB_PK"
send "$LOCKER" "unlock()"                                        --private-key "$BOB_PK"

# Fast-forward 14 days
warp 1209601; mine 1

BOB_BEFORE=$(call "$TOKEN" "balanceOf(address)(uint256)" "$BOB")
send "$LOCKER" "withdraw()" --private-key "$BOB_PK"
BOB_AFTER=$(call "$TOKEN" "balanceOf(address)(uint256)" "$BOB")

assert_eq "$(call "$LOCKER" "lockStateOf(address)(uint8)" "$BOB")"  "0"       "Bob state = Idle"
assert_eq "$(call "$LOCKER" "balanceOf(address)(uint256)" "$BOB")"  "0"       "Locker balance zeroed"
assert_eq "$BOB_BEFORE" "0"        "Bob token balance was 0 before withdraw"
assert_eq "$BOB_AFTER"  "$BOB_AMT" "Bob received 100 M back"

# ═════════════════════════════════════════════════════════════════
#  9. Governance — propose → vote → queue → execute (ETH)
# ═════════════════════════════════════════════════════════════════
step "Governance: ETH withdrawal proposal"

mine 1   # checkpoint block

WITHDRAW_CD=$(cast calldata "withdraw(address,address,uint256)" "$ADDR_ZERO" "$ALICE" "1000000000000000000")
DESC="Send 1 ETH to Alice"
DESC_HASH=$(cast keccak -- "$DESC")

PROPOSAL_ID=$(call "$GOVERNOR" \
    "hashProposal(address[],uint256[],bytes[],bytes32)(uint256)" \
    "[$TREASURY]" "[0]" "[$WITHDRAW_CD]" "$DESC_HASH")
echo "  Proposal ID: $PROPOSAL_ID"

# Propose
send "$GOVERNOR" "propose(address[],uint256[],bytes[],string)" \
    "[$TREASURY]" "[0]" "[$WITHDRAW_CD]" "$DESC" \
    --private-key "$ALICE_PK"
assert_eq "$(call "$GOVERNOR" "state(uint256)(uint8)" "$PROPOSAL_ID")" "0" "State = Pending"

# Advance past voting delay (1 block)
mine 2
assert_eq "$(call "$GOVERNOR" "state(uint256)(uint8)" "$PROPOSAL_ID")" "1" "State = Active"

# Vote For (support = 1)
send "$GOVERNOR" "castVote(uint256,uint8)" "$PROPOSAL_ID" 1 --private-key "$ALICE_PK"
pass "Alice voted For"

# Advance past voting period (10 blocks)
mine 11
assert_eq "$(call "$GOVERNOR" "state(uint256)(uint8)" "$PROPOSAL_ID")" "4" "State = Succeeded"

# Queue through Timelock
send "$GOVERNOR" "queue(address[],uint256[],bytes[],bytes32)" \
    "[$TREASURY]" "[0]" "[$WITHDRAW_CD]" "$DESC_HASH" \
    --private-key "$ALICE_PK"
assert_eq "$(call "$GOVERNOR" "state(uint256)(uint8)" "$PROPOSAL_ID")" "5" "State = Queued"

# Advance past timelock delay (1 s)
warp 2; mine 1

# Execute
send "$GOVERNOR" "execute(address[],uint256[],bytes[],bytes32)" \
    "[$TREASURY]" "[0]" "[$WITHDRAW_CD]" "$DESC_HASH" \
    --private-key "$ALICE_PK"
assert_eq "$(call "$GOVERNOR" "state(uint256)(uint8)" "$PROPOSAL_ID")" "7" "State = Executed"

TREASURY_ETH=$(cast balance "$TREASURY" --rpc-url "$RPC")
assert_eq "$TREASURY_ETH" "9000000000000000000" "Treasury balance = 9 ETH"

# ═════════════════════════════════════════════════════════════════
#  10. Governance — propose → vote → queue → execute (ERC-20)
# ═════════════════════════════════════════════════════════════════
step "Governance: ERC-20 withdrawal proposal"

WITHDRAW_AMOUNT="500000000000000000000000"  # 500 K
WITHDRAW_CD2=$(cast calldata "withdraw(address,address,uint256)" "$TOKEN" "$BOB" "$WITHDRAW_AMOUNT")
DESC2="Send 500K YELLOW to Bob"
DESC_HASH2=$(cast keccak -- "$DESC2")

PROPOSAL_ID2=$(call "$GOVERNOR" \
    "hashProposal(address[],uint256[],bytes[],bytes32)(uint256)" \
    "[$TREASURY]" "[0]" "[$WITHDRAW_CD2]" "$DESC_HASH2")

send "$GOVERNOR" "propose(address[],uint256[],bytes[],string)" \
    "[$TREASURY]" "[0]" "[$WITHDRAW_CD2]" "$DESC2" \
    --private-key "$ALICE_PK"

mine 2
send "$GOVERNOR" "castVote(uint256,uint8)" "$PROPOSAL_ID2" 1 --private-key "$ALICE_PK"
mine 11

send "$GOVERNOR" "queue(address[],uint256[],bytes[],bytes32)" \
    "[$TREASURY]" "[0]" "[$WITHDRAW_CD2]" "$DESC_HASH2" \
    --private-key "$ALICE_PK"

warp 2; mine 1

send "$GOVERNOR" "execute(address[],uint256[],bytes[],bytes32)" \
    "[$TREASURY]" "[0]" "[$WITHDRAW_CD2]" "$DESC_HASH2" \
    --private-key "$ALICE_PK"

assert_eq "$(call "$GOVERNOR" "state(uint256)(uint8)" "$PROPOSAL_ID2")" "7" "State = Executed"

REMAINING="500000000000000000000000"  # 1 M - 500 K = 500 K
assert_eq "$(call "$TOKEN" "balanceOf(address)(uint256)" "$TREASURY")" "$REMAINING" "Treasury YELLOW = 500 K"
pass "Bob received 500 K YELLOW"

# ═════════════════════════════════════════════════════════════════
#  11. Governance — defeated proposal
# ═════════════════════════════════════════════════════════════════
step "Governance: defeated proposal"

WITHDRAW_CD3=$(cast calldata "withdraw(address,address,uint256)" "$ADDR_ZERO" "$BOB" "1000000000000000000")
DESC3="Drain ETH (should fail)"
DESC_HASH3=$(cast keccak -- "$DESC3")

PROPOSAL_ID3=$(call "$GOVERNOR" \
    "hashProposal(address[],uint256[],bytes[],bytes32)(uint256)" \
    "[$TREASURY]" "[0]" "[$WITHDRAW_CD3]" "$DESC_HASH3")

send "$GOVERNOR" "propose(address[],uint256[],bytes[],string)" \
    "[$TREASURY]" "[0]" "[$WITHDRAW_CD3]" "$DESC3" \
    --private-key "$ALICE_PK"

mine 2

# Vote Against (support = 0)
send "$GOVERNOR" "castVote(uint256,uint8)" "$PROPOSAL_ID3" 0 --private-key "$ALICE_PK"
pass "Alice voted Against"

mine 11
assert_eq "$(call "$GOVERNOR" "state(uint256)(uint8)" "$PROPOSAL_ID3")" "3" "State = Defeated"

# ═════════════════════════════════════════════════════════════════
#  Done
# ═════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  All integration tests passed${NC}"
echo -e "${GREEN}══════════════════════════════════════════════${NC}"
