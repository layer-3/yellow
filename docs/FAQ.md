# Frequently Asked Questions

## General

### What is Yellow Network governance?

Node operators lock YELLOW tokens in the NodeRegistry to gain voting power and participate in on-chain governance through proposals. App owners lock YELLOW as collateral in the AppRegistry where misbehaviour can be penalised via slashing.

### What contracts are involved?

| Contract | Role |
|---|---|
| **YellowToken** | ERC-20 token (fixed 10B supply, no mint/burn) |
| **NodeRegistry** | Lock YELLOW to get voting power (node operators) |
| **AppRegistry** | Lock YELLOW as collateral, subject to slashing (app owners) |
| **YellowGovernor** | Create and vote on proposals |
| **TimelockController** | Enforces a delay before execution |
| **Treasury** | Holds Layer-3 Foundation assets (ETH and ERC-20s) |

---

## NodeRegistry (Node Operators)

### How do I get voting power?

1. Approve the NodeRegistry to spend your YELLOW tokens.
2. Call `lock(yourAddress, amount)` on the NodeRegistry.

Voting power activates automatically — the contract auto-self-delegates on your first lock.

### Can I add more tokens to an existing lock?

Yes. Call `lock(yourAddress, amount)` again while in the **Locked** state. You cannot top up while in the **Unlocking** state.

### Can I delegate my votes to someone else?

Yes. Call `delegate(theirAddress)` on the NodeRegistry. You can change your delegate at any time.

### How do I get my tokens back?

Two-step process:

```
unlock()   →  wait 14 days  →  withdraw(destination)
```

1. Call `unlock()` to start the countdown.
2. After the period elapses, call `withdraw(destination)` to receive your full balance.

Your voting power is removed the moment you call `unlock()`.

### Can I cancel an unlock?

Yes. Call `relock()` before withdrawing. Your tokens stay locked and voting power is restored.

---

## AppRegistry (App Owners)

### How does it differ from NodeRegistry?

Same lock/unlock/withdraw state machine, but **no voting power**. AppRegistry is purely for collateral management and slashing.

### What is slashing?

If an app owner violates protocol rules, an address with `ADJUDICATOR_ROLE` can call `slash(user, amount, recipient, decision)` to confiscate part or all of their locked collateral. Slashed tokens are transferred to the specified recipient.

### Can I be slashed while unlocking?

Yes. Slashing applies in both **Locked** and **Unlocking** states. If your entire balance is slashed, your state resets to **Idle**.

### What is the slash cooldown?

A global rate-limit on slashing. When set (via governance), only one slash can occur per cooldown window. This prevents a rogue adjudicator from draining all users in a single transaction, giving governance time to revoke the role.

---

## Proposals

### Who can create a proposal?

Anyone with at least **10 million YELLOW** in voting power (the default proposal threshold).

### What does the proposal lifecycle look like?

```
Propose → Voting Delay (~1 day) → Voting Period (~1 week) → Queue → Timelock (~2 days) → Execute
```

### How do I vote?

Call `castVote(proposalId, support)` on the Governor:

- `0` = Against
- `1` = For
- `2` = Abstain

### What is quorum?

The minimum votes required for a proposal to be valid. Calculated as `max(4% of total locked supply, 100M YELLOW)`. The floor prevents proposals from passing with very few votes when locked supply is low.

### Can a proposal be cancelled?

- The **proposer** can cancel while the proposal is Pending.
- The **proposal guardian** (Foundation multisig) can cancel any proposal as an emergency brake.

---

## Treasury

### What can the Treasury hold?

ETH and any ERC-20 token.

### How are funds transferred from the Treasury?

Call `transfer(token, to, amount)` where `token` is `address(0)` for ETH or an ERC-20 address.

If the Treasury is owned by the TimelockController, this requires a governance proposal. If owned directly by the Foundation, the owner can call it directly.

---

## Parameters

| Parameter | Default | Changeable via |
|---|---|---|
| Total YELLOW supply | 10,000,000,000 | Fixed (no mint/burn) |
| Proposal threshold | 10,000,000 YELLOW | Governance |
| Voting delay | ~1 day (7,200 blocks) | Governance |
| Voting period | ~1 week (50,400 blocks) | Governance |
| Quorum | 4% of locked supply | Governance |
| Quorum floor | 100,000,000 YELLOW | Governance |
| Vote extension | ~2 days (14,400 blocks) | Governance |
| NodeRegistry unlock period | 14 days | Immutable (set at deploy) |
| AppRegistry unlock period | 14 days | Immutable (set at deploy) |
| Timelock delay | 2 days | Governance |
| Slash cooldown | 0 (disabled) | Governance |
