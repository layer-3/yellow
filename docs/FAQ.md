# Yellow Network Governance FAQ

## General

### What is Yellow governance?

Node operators lock YELLOW tokens in the NodeRegistry to gain voting power and participate in on-chain governance through proposals. App owners lock YELLOW as collateral in the AppRegistry where misbehaviour can be penalised via slashing.

### What contracts are involved?

| Contract | Role |
|---|---|
| **YellowToken** | The ERC-20 token (fixed 10B supply, no mint/burn) |
| **NodeRegistry** | Lock YELLOW to get voting power (node operators) |
| **AppRegistry** | Lock YELLOW as collateral, subject to slashing (app owners) |
| **YellowGovernor** | Create and vote on proposals |
| **TimelockController** | Enforces a delay before execution |
| **Treasury** | Holds Layer-3 Foundation assets (ETH and ERC-20s) |

---

## NodeRegistry (Node Operators)

### How do I get voting power?

1. Approve the NodeRegistry to spend your YELLOW tokens.
2. Call `lock(amount)` on the NodeRegistry.
3. Call `delegate(yourAddress)` to activate your own voting power.

Step 3 is easy to forget -- **your votes won't count until you delegate**, even to yourself.

### Can I add more tokens to an existing lock?

Yes. Call `lock(amount)` again while in the **Locked** state and it adds to your balance. You cannot top up while you are in the **Unlocking** state.

### Can I delegate my votes to someone else?

Yes. Call `delegate(theirAddress)` on the NodeRegistry. The delegate receives your full voting power. You can change your delegate at any time.

### How do I get my tokens back?

It's a two-step process:

```
unlock()   -->  wait 14 days  -->  withdraw()
```

1. Call `unlock()` to start the countdown (default 14 days).
2. After the period elapses, call `withdraw()` to receive your full balance.

Your voting power is removed the moment you call `unlock()`.

### Can I cancel an unlock?

Yes. Call `relock()` at any time before `withdraw()`. Your tokens stay locked and voting power is restored.

### What if I try to lock tokens while unlocking?

The transaction reverts with `AlreadyUnlocking`. Cancel the unlock with `relock()` first, then lock additional tokens.

---

## AppRegistry (App Owners)

### How does the AppRegistry work?

App owners lock YELLOW as collateral. The lock/unlock/withdraw state machine is the same as NodeRegistry, but there is **no voting power** -- the AppRegistry does not participate in governance.

### What is slashing?

If an app owner violates protocol rules, the **adjudicator** can call `slash(user, amount)` to confiscate part or all of their locked collateral. Slashed tokens are transferred to the adjudicator for redistribution.

### Can I be slashed while unlocking?

Yes. Slashing applies in both the **Locked** and **Unlocking** states. Starting an unlock does not protect you from slashing. If your entire balance is slashed, your state resets to **Idle**.

### Who is the adjudicator?

The adjudicator is an address set at deployment that is authorised to slash participants. It may be a multisig, a dispute resolution contract, or another mechanism determined by the Layer-3 Foundation.

---

## Proposals

### Who can create a proposal?

Anyone with at least **10 million YELLOW** in voting power (the default proposal threshold).

### What does the proposal lifecycle look like?

```
Propose  -->  Voting Delay (~1 day)  -->  Voting Period (~1 week)  -->  Queue  -->  Timelock (~2 days)  -->  Execute
```

1. **Propose** -- submit the proposal on-chain.
2. **Voting delay** -- ~1 day (7,200 blocks) before voting opens.
3. **Voting period** -- ~1 week (50,400 blocks) for token holders to vote.
4. **Queue** -- if it passes quorum and majority, queue it in the Timelock.
5. **Timelock delay** -- 2-day waiting period for stakeholders to review.
6. **Execute** -- anyone can trigger execution after the delay.

### How do I vote?

Call `castVote(proposalId, support)` on the Governor where `support` is:

- `0` = Against
- `1` = For
- `2` = Abstain

### What is quorum?

The minimum number of votes required for a proposal to be valid. It's calculated as 4% of total locked supply, but never less than **100 million YELLOW** (the quorum floor). This prevents proposals from passing with very few votes when total locked supply is low.

### Can a proposal be cancelled?

Yes, the Governor can cancel a proposal before it's executed.

---

## Treasury

### What can the Treasury hold?

ETH and any ERC-20 token. It has a `receive()` function so it can accept ETH transfers directly.

### How are funds withdrawn from the Treasury?

The Treasury is owned by the Layer-3 Foundation. The Foundation address can call `withdraw()` directly -- no governance vote is required.

### Who owns the Treasury?

The Layer-3 Foundation, via direct ownership (`Ownable2Step`). This is different from the governance-controlled model -- the Foundation manages treasury assets independently.

---

## Defaults & Parameters

| Parameter | Default | Notes |
|---|---|---|
| Total YELLOW supply | 10,000,000,000 | Fixed, no mint/burn |
| Proposal threshold | 10,000,000 YELLOW | Minimum voting power to propose |
| Voting delay | ~1 day | 7,200 blocks at 12s/block |
| Voting period | ~1 week | 50,400 blocks at 12s/block |
| Quorum | 4% of locked supply | Never below 100M YELLOW floor |
| NodeRegistry unlock period | 14 days | Node operator withdrawal waiting period |
| AppRegistry unlock period | 14 days | App owner withdrawal waiting period |
| Timelock delay | 2 days | Delay before proposal execution |

### Can these parameters be changed?

Yes, governance parameters can be changed through governance. The Governor inherits `GovernorSettings` which allows updating voting delay, voting period, and proposal threshold via proposals. The quorum floor can also be updated via `setQuorumFloor()`, which is restricted to governance-only.
