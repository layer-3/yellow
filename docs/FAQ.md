# Yellow Network Governance FAQ

## General

### What is Yellow governance?

Token holders lock YELLOW tokens to gain voting power and collectively manage the DAO treasury through on-chain proposals. Every decision -- from funding a grant to changing governance parameters -- goes through a transparent vote.

### What contracts are involved?

| Contract | Role |
|---|---|
| **YellowToken** | The ERC-20 token (fixed 10B supply, no mint/burn) |
| **Locker** | Lock YELLOW to get voting power |
| **YellowGovernor** | Create and vote on proposals |
| **TimelockController** | Enforces a delay before execution |
| **Treasury** | Holds DAO assets (ETH and ERC-20s) |

---

## Locking & Voting Power

### How do I get voting power?

1. Approve the Locker to spend your YELLOW tokens.
2. Call `lock(amount)` on the Locker.
3. Call `delegate(yourAddress)` to activate your own voting power.

Step 3 is easy to forget -- **your votes won't count until you delegate**, even to yourself.

### Can I add more tokens to an existing lock?

Yes. Call `lock(amount)` again while in the **Locked** state and it adds to your balance. You cannot top up while you are in the **Unlocking** state.

### Can I delegate my votes to someone else?

Yes. Call `delegate(theirAddress)` on the Locker. The delegate receives your full voting power. You can change your delegate at any time.

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

Only through a governance vote. A proposal must pass, survive the timelock delay, and then anyone can execute it. The Treasury's `withdraw()` function supports both ETH (`token = address(0)`) and ERC-20 tokens.

### Who owns the Treasury?

The TimelockController, via a two-step ownership transfer (`Ownable2Step`). No single person or key can move funds -- it requires a full governance vote.

---

## Defaults & Parameters

| Parameter | Default | Notes |
|---|---|---|
| Total YELLOW supply | 10,000,000,000 | Fixed, no mint/burn |
| Proposal threshold | 10,000,000 YELLOW | Minimum voting power to propose |
| Voting delay | ~1 day | 7,200 blocks at 12s/block |
| Voting period | ~1 week | 50,400 blocks at 12s/block |
| Quorum | 4% of locked supply | Never below 100M YELLOW floor |
| Unlock period | 14 days | Locker withdrawal waiting period |
| Timelock delay | 2 days | Delay before proposal execution |

### Can these parameters be changed?

Yes, through governance. The Governor inherits `GovernorSettings` which allows updating voting delay, voting period, and proposal threshold via proposals. The quorum floor can also be updated via `setQuorumFloor()`, which is restricted to governance-only.
