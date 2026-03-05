# Staking

Both NodeRegistry and AppRegistry implement the `ILock` interface — a single-asset vault with a time-locked withdrawal mechanism. Users lock YELLOW tokens, initiate an unlock, wait for the period to elapse, then withdraw.

## State Machine

```
        lock(target, amount)       unlock()            withdraw(destination)
  Idle ──────────────────► Locked ──────────► Unlocking ─────────────────► Idle
                              │                   │
                        lock() top-up          relock()
                        (stays Locked)     (back to Locked)
```

### States

| State | Value | Description |
|---|---|---|
| Idle | 0 | No locked balance |
| Locked | 1 | Tokens are locked, can top up |
| Unlocking | 2 | Countdown started, waiting for unlock period |

## Functions

### lock(target, amount)

Deposits `amount` YELLOW tokens into the vault, crediting `target`. The caller must have approved the registry to spend their tokens. Can be called multiple times to top up while in the Locked state.

- **Reverts** if `target` is in Unlocking state (`AlreadyUnlocking`)
- **Reverts** if `amount` is zero (`InvalidAmount`)
- Anyone can lock tokens on behalf of another address

### unlock()

Starts the withdrawal countdown for the caller's full balance. The unlock period is set at deployment (default 14 days).

- **Reverts** if caller has no locked balance (`NotLocked`)
- **Reverts** if already unlocking (`AlreadyUnlocking`)
- **NodeRegistry:** immediately removes voting power

### relock()

Cancels an in-progress unlock and returns to the Locked state.

- **Reverts** if not in Unlocking state (`NotUnlocking`)
- **NodeRegistry:** immediately restores voting power

### withdraw(destination)

Transfers the caller's full locked balance to `destination` after the unlock period has elapsed.

- **Reverts** if not in Unlocking state (`NotUnlocking`)
- **Reverts** if countdown hasn't finished (`UnlockPeriodNotElapsed`)
- Resets state to Idle

## View Functions

| Function | Returns | Description |
|---|---|---|
| `asset()` | `address` | YELLOW token address |
| `UNLOCK_PERIOD()` | `uint256` | Withdrawal delay in seconds |
| `lockStateOf(address)` | `LockState` | Current state (0/1/2) |
| `balanceOf(address)` | `uint256` | Locked balance |
| `unlockTimestampOf(address)` | `uint256` | When withdrawal becomes available (0 if not unlocking) |

## NodeRegistry vs AppRegistry

| Feature | NodeRegistry | AppRegistry |
|---|---|---|
| Voting power | Yes (OZ `Votes`) | No |
| Auto-self-delegation | Yes (on first lock) | N/A |
| Delegation | Yes (`delegate(address)`) | N/A |
| Slashing | No | Yes (`ADJUDICATOR_ROLE`) |
| Slash cooldown | N/A | Yes (`setSlashCooldown`) |
| Access control | Open | `AccessControl` (admin + adjudicator roles) |

## Events

| Event | Parameters | When |
|---|---|---|
| `Locked` | `user`, `deposited`, `newBalance` | Tokens locked |
| `UnlockInitiated` | `user`, `balance`, `availableAt` | Unlock started |
| `Relocked` | `user`, `balance` | Unlock cancelled |
| `Withdrawn` | `user`, `balance` | Tokens withdrawn |
