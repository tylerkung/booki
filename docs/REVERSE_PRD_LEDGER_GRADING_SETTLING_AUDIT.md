# Reverse PRD: Booki Ledger, Grading, Settling & Audit System

> **What this document is:** A complete specification of the existing system as currently implemented. Written as a reverse-engineered PRD so that any developer can understand, maintain, or extend the financial engine without reading source code.

---

## 1. System Overview

Booki uses a **server-authoritative, append-only ledger** to track all financial activity between bookies and players. Every balance-affecting action flows through Supabase Edge Functions that validate authorization, enforce business rules, write to the ledger, and emit audit events. The iOS client never writes financial data directly — it calls edge functions and mirrors the response locally in SwiftData.

### Core Principles

- **No stored balances.** Balances are always derived by summing ledger entries. There is no `balance` column on any table.
- **Append-only ledger.** Entries are never updated or deleted. Corrections are made by inserting reversal entries with the opposite amount.
- **Server authority.** All state transitions (grading, settling, adjusting) happen in edge functions using a service-role Supabase client that bypasses RLS.
- **Idempotency.** Every mutation accepts an `idempotency_key`. Duplicate requests return the cached response instead of double-processing.
- **Full audit trail.** Every state change emits an audit event with before/after snapshots, actor ID, and optional reason.

---

## 2. Data Model

### 2.1 Bet Lifecycle (BetStatus)

```
pending → accepted → graded → settled
   │          │         │
   │          │         └──→ (override_grade) → graded → settled
   │          │
   │          └──→ void (cancelled, no payout)
   │
   └──→ declined (rejected by bookie, terminal)
```

| Status | Meaning | Can transition to |
|--------|---------|-------------------|
| `pending` | Submitted, awaiting bookie acceptance | `accepted`, `declined`, `void` |
| `accepted` | Live bet, stake committed | `graded`, `settled`*, `void` |
| `declined` | Bookie rejected the bet (terminal) | — |
| `readyToGrade` | Event finished, ready for grading (unused in prod) | — |
| `graded` | Outcome determined (win/loss/push) | `settled` |
| `settled` | Ledger entry created, balance updated (terminal) | `graded`** |
| `void` | Bet cancelled, no payout (terminal) | — |

\* Auto-pilot skips `graded` and goes `accepted → settled` directly.
\** `reverse_settlement` moves `settled → graded` for re-grading.

### 2.2 GradeResult

| Value | Meaning | Ledger impact |
|-------|---------|---------------|
| `win` | Player won | Negative amount (bookie owes player profit) |
| `loss` | Player lost | Positive amount (player owes bookie the stake) |
| `push` | Tie / no action | Zero amount (no ledger entry in auto-pilot; $0 entry in manual settle) |

### 2.3 LedgerEntry

**Append-only. Never updated or deleted.**

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `bookie_id` | UUID | Multi-tenant isolation |
| `player_id` | UUID | Which player this entry belongs to |
| `bet_id` | UUID? | Source bet (null for adjustments/payments) |
| `amount` | Decimal | Signed amount (see convention below) |
| `type` | EntryType | Category of entry |
| `description` | String | Human-readable explanation |
| `created_at` | Timestamp | Immutable creation time |

#### Amount Convention (Internal)

| Amount | Meaning |
|--------|---------|
| **Positive** | Player owes bookie (player debt increases) |
| **Negative** | Bookie owes player (player credit increases) |

For player-facing display, **negate** the internal value: positive = credit (green), negative = debt (red).

#### EntryType

| Type | Created by | Amount | Description |
|------|-----------|--------|-------------|
| `settlement` | `settle_bet`, `auto_refresh_games` | Win: `-profit`, Loss: `+stake`, Push/Void: `0` | "Bet won" / "Bet lost" / "Bet pushed" / "Bet voided" |
| `adjustment` | `adjust_balance` | Any signed decimal | Bookie-provided reason string |
| `paymentLogged` | `adjust_balance` | Negative (reduces debt) | "Payment received" or similar |
| `reversal` | `reverse_settlement`, `override_grade` | Opposite of original settlement | "Settlement reversal: {reason}" |

### 2.4 AuditEvent

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `bookie_id` | UUID | Owning bookie |
| `actor_user_id` | UUID | Who triggered the action (auth.users FK) |
| `entity_type` | String | `bet`, `ledger_entry`, `player`, `event`, `invite` |
| `entity_id` | UUID | Which record was affected |
| `action_type` | String | What happened (see table below) |
| `previous_state` | JSONB? | Snapshot before change |
| `new_state` | JSONB | Snapshot after change |
| `reason` | String? | Optional explanation |
| `created_at` | Timestamp | When it happened |

#### Action Types

| action_type | Emitted by | Description |
|-------------|-----------|-------------|
| `grade` | `grade_bet` | Manual grading of a bet |
| `settle` | `settle_bet` | Manual settlement |
| `adjust` | `adjust_balance` | Manual balance adjustment |
| `reverse` | `reverse_settlement`, `override_grade` | Settlement reversal |
| `override` | `override_grade` | Grade changed after initial grading |
| `decline` | `decline_bet` | Bookie rejected a pending bet |
| `create` | `settle_bet`, `reverse_settlement`, `override_grade`, `adjust_balance` | New ledger entry created |
| `bet_auto_settled` | `auto_refresh_games` | Auto-grade + auto-settle in one step |
| `bet_auto_voided` | `auto_refresh_games` (catch-up) | Pending bet voided because event finalized |
| `event_finalized_auto` | `auto_refresh_games` | Event reached final status |
| `odds_refreshed_auto` | `auto_refresh_games` | Market odds updated from API |
| `score_refreshed_auto` | `auto_refresh_games` | Event scores updated from API |

### 2.5 IdempotencyKey

| Field | Type | Description |
|-------|------|-------------|
| `key` | String | Client-generated unique key |
| `operation` | String | Function name (e.g., `settle_bet`) |
| `response` | Text | Cached JSON response |
| `user_id` | UUID | Who made the request |
| `created_at` | Timestamp | When cached |
| `expires_at` | Timestamp | `created_at + 24h` |

**Constraint:** `UNIQUE(key, operation)`

---

## 3. Balance Calculation (Client-Side)

All balances are derived — never stored. The iOS `BalanceService` computes everything from raw data.

### 3.1 Core Formula

```
availableCredit = creditLimit - openStakes - balanceOwed
```

Where:
- **creditLimit** — Set by bookie per player
- **openStakes** — Sum of `stake` on all `pending` + `accepted` bets (excluded: declined, graded, settled, void)
- **balanceOwed** — Sum of all `ledger_entries.amount` for the player (positive = player owes)

### 3.2 Open Liability (Bookie-Facing)

```
openLiability = Σ calculatePayout(stake, odds) for each pending/accepted bet
```

This is the total the bookie would owe if every active bet won. Used for exposure tracking, not credit calculation.

### 3.3 Payout Calculation (American Odds)

```
if odds > 0:  profit = stake × (odds / 100)      // +150: $100 → $150 profit
if odds < 0:  profit = stake × (100 / |odds|)     // -110: $110 → $100 profit
```

Returns **profit only** (not including original stake return).

### 3.4 What Happens to Credit on Each Status

| Status Change | Effect on `openStakes` | Effect on `balanceOwed` |
|--------------|----------------------|----------------------|
| Bet submitted (accepted) | +stake | No change |
| Bet declined | -stake (removed from active) | No change |
| Bet graded | Still active until settled | No change |
| Bet settled (win) | -stake (no longer active) | -profit (bookie owes player) |
| Bet settled (loss) | -stake (no longer active) | +stake (player owes bookie) |
| Bet settled (push) | -stake (no longer active) | No change ($0 entry) |
| Bet voided | -stake (no longer active) | No change |

---

## 4. Edge Functions — Complete Specification

### 4.1 `grade_bet` — Manual Grading

**Purpose:** Bookie assigns an outcome to an accepted bet.

| Field | Required | Type | Notes |
|-------|----------|------|-------|
| `bet_id` | Yes | UUID | Must be `accepted` status |
| `outcome` | Yes | `win` / `loss` / `push` / `void` | |
| `idempotency_key` | Yes | String | |

**Behavior:**
1. Validate JWT → extract bookie
2. Verify bet belongs to bookie
3. Verify bet status is `accepted`
4. If outcome is `void`: set status → `void`, grade_result → null
5. Otherwise: set status → `graded`, grade_result → outcome
6. Emit audit event (`grade`)
7. **Does NOT create a ledger entry** — that's `settle_bet`'s job

**Idempotency key format:** `grade_{betId}_{timestamp}`

### 4.2 `settle_bet` — Settlement & Ledger Creation

**Purpose:** Creates the ledger entry for a graded bet and marks it settled.

| Field | Required | Type | Notes |
|-------|----------|------|-------|
| `bet_id` | Yes | UUID | Must be `graded` status with non-null `grade_result` |
| `idempotency_key` | Yes | String | |

**Behavior:**
1. Validate JWT → extract bookie
2. Verify bet belongs to bookie
3. Verify bet has `grade_result` and status is `graded`
4. Calculate payout:
   - Win: `-profit` (negative = bookie owes player)
   - Loss: `+stake` (positive = player owes bookie)
   - Push/Void: `0`
5. Update bet status → `settled`
6. Insert `ledger_entries` row (type: `settlement`)
7. Emit 2 audit events: one for bet status change, one for ledger entry creation
8. Return bet + ledger_entry in response

**Idempotency key format:** `settle_{betId}_{timestamp}`

**Known limitation:** Bet update and ledger insert are not in a DB transaction. If ledger insert fails after bet update, the bet is marked settled without a ledger entry. Error is logged and returned.

### 4.3 `decline_bet` — Bookie Rejection

**Purpose:** Bookie rejects a pending bet. Terminal state, no financial impact.

| Field | Required | Type | Notes |
|-------|----------|------|-------|
| `bet_id` | Yes | UUID | Must be `pending` status |
| `idempotency_key` | Yes | String | |

**Behavior:**
1. Validate JWT → extract bookie
2. Verify bet belongs to bookie
3. Verify bet status is `pending` (cannot decline accepted/graded/settled bets)
4. Update bet status → `declined`
5. Emit audit event (`decline`)
6. **No ledger entry created** — stake was held as `openStakes`, now released

### 4.4 `adjust_balance` — Manual Balance Adjustment

**Purpose:** Bookie manually adjusts a player's balance (payments, corrections, credits).

| Field | Required | Type | Notes |
|-------|----------|------|-------|
| `player_id` | Yes | UUID | Must belong to requesting bookie |
| `amount` | Yes | String (decimal) | Any signed value |
| `reason` | Yes | String | Non-empty explanation |
| `idempotency_key` | Yes | String | |

**Behavior:**
1. Validate JWT → extract bookie
2. Verify player belongs to bookie
3. Parse amount as float
4. Insert `ledger_entries` row (type: `adjustment`, bet_id: null)
5. Emit audit event (`adjust`)

### 4.5 `reverse_settlement` — Undo a Settlement

**Purpose:** Reverses a settled bet's ledger entry and returns the bet to `graded` status for re-processing.

| Field | Required | Type | Notes |
|-------|----------|------|-------|
| `bet_id` | Yes | UUID | Must be `settled` status |
| `reason` | Yes | String | Non-empty explanation |
| `idempotency_key` | Yes | String | |

**Behavior:**
1. Validate JWT → extract bookie
2. Verify bet belongs to bookie, status is `settled`
3. Find the most recent `settlement` type ledger entry for this bet
4. Create reversal entry: amount = `-originalAmount`, type = `reversal`
5. Update bet status → `graded` (grade_result preserved)
6. Emit 2 audit events: bet reversal + reversal ledger entry creation

### 4.6 `override_grade` — Change a Bet's Grade

**Purpose:** Changes the grade_result of a bet that has already been graded. If the bet was already settled, automatically reverses the settlement first.

| Field | Required | Type | Notes |
|-------|----------|------|-------|
| `bet_id` | Yes | UUID | Must have non-null `grade_result` |
| `new_outcome` | Yes | `win` / `loss` / `push` / `void` | |
| `reason` | Yes | String | Non-empty explanation |
| `idempotency_key` | Yes | String | |

**Behavior:**
1. Validate JWT → extract bookie
2. Verify bet has been graded (`grade_result` is not null)
3. **If bet is `settled`:**
   - Find most recent settlement ledger entry
   - Create reversal entry (opposite amount, type `reversal`)
   - Emit audit events for reversal
4. Update bet: status → `graded`, grade_result → new_outcome
5. Emit audit event (`override`) with before/after state
6. **Does NOT re-settle** — bookie must call `settle_bet` again manually

### 4.7 `auto_refresh_games` — Cron-Based Auto-Grade & Settle

**Purpose:** Fetches live scores, auto-grades bets on finalized events, creates ledger entries, and catches up on missed events.

**Schedule:** Every 2 hours (9 runs/day), processes up to 25 games per run.

**Idempotency key format:** `auto_refresh_{YYYY-MM-DD}_{window}` (window = morning/afternoon based on UTC hour)

#### Main Flow (Score Refresh → Auto-Settle)

For each game with accepted bets:
1. Fetch scores from The Odds API
2. If event just reached `final` status with valid scores:
   a. Check bookie's `manual_bet_grading` setting — skip if enabled
   b. Query all `accepted` bets on this event
   c. For each bet:
      - Run grading logic (see Section 5)
      - **Skip `graded` status entirely** — go straight to `settled`
      - Calculate payout amount
      - **Only create ledger entry if payout != 0** (push/void = no entry)
      - Emit audit event (`bet_auto_settled`)

#### Catch-Up Grading

Runs after the main flow. No API calls — pure database work.

1. **Grade stranded accepted bets:**
   - Find all bets with status `accepted`
   - Check if their events are `final` with valid scores
   - Skip if bookie has `manual_bet_grading` enabled
   - Grade + settle each bet (same logic as main flow)

2. **Void stale pending bets:**
   - Find all bets with status `pending`
   - If their event is `final` OR started 6+ hours ago:
     - Set status → `void`, grade_result → `void`
     - Emit audit event (`bet_auto_voided`)
     - **No ledger entry** — pending bets never had committed stake in the ledger

---

## 5. Grading Logic (Server-Side)

All grading logic lives in `_shared/grading.ts`. The `gradeBet()` dispatcher routes to market-specific functions.

### 5.1 Moneyline / H2H

```
Input: bet.side = "Lakers", scores = { home: 105, away: 100, homeTeam: "Lakers" }

1. Determine which team bettor picked (substring match against homeTeam/awayTeam)
2. Compare bettor's team score vs opponent score:
   - Higher → WIN
   - Lower → LOSS
   - Equal → PUSH
```

### 5.2 Spread

```
Input: bet.side = "Lakers -3.5", scores = { home: 105, away: 100 }

1. Extract numeric spread from side string: -3.5
2. Determine which team bettor picked
3. adjustedScore = bettorScore + spread
4. Compare adjustedScore vs opponentScore:
   - Higher → WIN
   - Lower → LOSS
   - Equal → PUSH

Example: Lakers 105, spread -3.5 → 105 + (-3.5) = 101.5 > 100 → WIN
```

### 5.3 Total (Over/Under)

```
Input: bet.side = "Over 220.5", scores = { home: 105, away: 100 }

1. Extract numeric total from side string: 220.5
2. Determine if Over or Under from side string
3. combinedScore = homeScore + awayScore = 205
4. Compare:
   - Over: combined > total → WIN, < total → LOSS, == → PUSH
   - Under: combined < total → WIN, > total → LOSS, == → PUSH
```

### 5.4 Team Total

Same as Total but uses individual team's score instead of combined.

### 5.5 Outright / Futures

```
Returns: PUSH with message "manual grading required"
```

Futures cannot be auto-graded. Bookie must use `grade_bet` manually.

### 5.6 Unknown Market Types

Returns PUSH as a safe default. Manual grading required.

### 5.7 Parse Failures

If the numeric value cannot be extracted from the side string (spread, total), returns PUSH to avoid incorrect grading. Bookie can override.

---

## 6. Parlay Grading (Client-Side)

Parlay outcome is computed by `ParlayGradingService` on the iOS client. All legs share the same `ticketId`.

### 6.1 Outcome Rules (evaluated in order)

1. **Any leg lost** → entire parlay is **LOSS** (terminal, regardless of other legs)
2. **Any legs still pending** → **PENDING** or **PARTIALLY_GRADED**
3. **All legs graded, no losses** → apply push/void policy

### 6.2 Push/Void Policies

| Policy | Behavior |
|--------|----------|
| `treatAsPush` | Any push/void leg → entire parlay is PUSH (stake returned) |
| `reduceLegReprice` | Remove push/void legs, recalculate payout with remaining winners only |

### 6.3 Payout Calculation

```
combinedMultiplier = 1.0
for each leg:
    decimalOdds = americanToDecimal(leg.odds)
    combinedMultiplier *= decimalOdds

totalPayout = stake × combinedMultiplier
profit = totalPayout - stake
```

Where `americanToDecimal`:
- Positive (+150): `1 + 150/100 = 2.5`
- Negative (-110): `1 + 100/110 = 1.909...`

### 6.4 Parlay Settlement (Client → Server)

`GradingService.settleParlayBets()` calls `settle_bet` for each leg sequentially:
- Skips already-settled and void legs
- Only the first leg's ledger entry response is mirrored locally in SwiftData
- Other legs' entries are created server-side only (will sync later)

---

## 7. Settlement Reports

`SettlementService` generates period-based financial reports for reconciliation.

### 7.1 Report Structure

```
startingBalance     = Σ ledger entries BEFORE periodStart
netBetResults       = Σ settlement entries IN period
paymentsReceived    = -Σ paymentLogged entries IN period (negated for display)
adjustments         = Σ adjustment + reversal entries IN period
endingBalance       = startingBalance + netBetResults - paymentsReceived + adjustments
```

Plus: `betsSettledCount`, `betsWonCount`, `betsLostCount` within the period.

---

## 8. Auto-Pilot vs Manual Mode

### 8.1 Auto-Pilot (Default)

The happy path for most bets:

```
Player submits bet
  → submit_bets: status = 'accepted' (auto-accept)
  → Event finalizes (scores come in)
  → auto_refresh_games: accepted → settled (skips 'graded')
  → Ledger entry created automatically
  → Balance updated (derived from new ledger sum)
```

No bookie interaction required.

### 8.2 Manual Acceptance Mode

Enabled per bookie via `manual_bet_acceptance` setting.

```
Player submits bet
  → submit_bets: status = 'pending'
  → Bookie reviews in Picks tab
  → Bookie accepts → grade_bet → settle_bet (or auto-refresh handles it)
  → OR Bookie declines → decline_bet (terminal, no ledger)
```

### 8.3 Manual Grading Mode

Enabled per bookie via `manual_bet_grading` setting.

```
Event finalizes
  → auto_refresh_games: SKIPS grading for this bookie
  → Bookie manually grades via grade_bet
  → Bookie manually settles via settle_bet
  → Ledger entry created
```

---

## 9. Correction Flows

### 9.1 Override Before Settlement

```
grade_bet(outcome: win) → bet is 'graded'
  Bookie realizes mistake
override_grade(new_outcome: loss, reason: "...")
  → grade_result: win → loss
  → status stays 'graded'
settle_bet → creates correct ledger entry
```

### 9.2 Override After Settlement

```
settle_bet → bet is 'settled', ledger entry exists
  Bookie realizes mistake
override_grade(new_outcome: loss, reason: "...")
  → Finds original settlement entry
  → Creates reversal entry (opposite amount)
  → grade_result: win → loss
  → status: settled → graded
settle_bet (again) → creates new correct ledger entry
```

Ledger trail after override of a settled win→loss:
```
1. settlement:  -$150.00  "Bet won"           (original)
2. reversal:    +$150.00  "Settlement reversal: Official review"
3. settlement:  +$100.00  "Bet lost"           (corrected)
Net effect: +$100.00 (player owes stake)
```

### 9.3 Standalone Reversal

```
reverse_settlement(reason: "...")
  → Creates reversal entry
  → Bet returns to 'graded'
  → Bookie can re-grade or re-settle
```

---

## 10. Terminal States Summary

| State | Ledger Entry? | Stake Released? | Can Be Corrected? |
|-------|--------------|----------------|-------------------|
| `settled` (win) | Yes, negative amount | Yes (no longer in openStakes) | Yes, via `override_grade` |
| `settled` (loss) | Yes, positive amount | Yes | Yes, via `override_grade` |
| `settled` (push) | Yes, zero amount | Yes | Yes, via `override_grade` |
| `void` | No* | Yes | No |
| `declined` | No | Yes (was pending, removed from openStakes) | No |

\* Void via `grade_bet` + `settle_bet` creates a $0 settlement entry. Void via `auto_refresh_games` does not create a ledger entry.

---

## 11. Known Limitations & Edge Cases

1. **Non-atomic settlement.** `settle_bet` updates the bet row first, then inserts the ledger entry. If the insert fails, the bet is marked `settled` without a corresponding ledger entry. The function returns an error but the bet status is already changed.

2. **Push/void ledger inconsistency.** Manual `settle_bet` always creates a ledger entry (even $0 for push/void). Auto-pilot (`auto_refresh_games`) only creates entries when `payoutAmount !== 0`, so push/void bets get no ledger row.

3. **Parlay settlement is per-leg.** Each parlay leg is settled independently via `settle_bet`. The overall parlay payout is calculated client-side; the server settles each leg with its own individual odds, not the combined parlay odds. This means the ledger entries per-leg don't reflect the actual parlay payout math — the first leg's entry carries the financial weight.

4. **Futures can't be auto-graded.** Outright/futures markets return `push` from the grading engine. Bookie must manually grade via `grade_bet`.

5. **Declined bets have no ledger trail.** A declined bet simply stops existing financially. The only record is the audit event and the bet's `declined` status.

6. **Catch-up void window.** Pending bets are voided if their event is `final` OR started 6+ hours ago. The 6-hour heuristic may be too aggressive for some sports (e.g., rain delays in baseball, extra innings).

7. **UUID case sensitivity.** iOS generates uppercase UUIDs, PostgreSQL stores lowercase. All comparisons must use `.lowercased()` / `.toLowerCase()`.

---

## 12. File Reference

### Edge Functions (Server)
| File | Purpose |
|------|---------|
| `supabase/functions/grade_bet/index.ts` | Manual grading |
| `supabase/functions/settle_bet/index.ts` | Manual settlement + ledger creation |
| `supabase/functions/decline_bet/index.ts` | Reject pending bet |
| `supabase/functions/adjust_balance/index.ts` | Manual balance adjustment |
| `supabase/functions/reverse_settlement/index.ts` | Undo a settlement |
| `supabase/functions/override_grade/index.ts` | Change grade (with auto-reversal if settled) |
| `supabase/functions/auto_refresh_games/index.ts` | Cron: scores, auto-grade, auto-settle, catch-up |
| `supabase/functions/_shared/grading.ts` | Market-specific grading logic |
| `supabase/functions/_shared/audit.ts` | `emitAuditEvent()` helper |
| `supabase/functions/_shared/idempotency.ts` | `checkIdempotency()` / `storeIdempotency()` |

### iOS Services
| File | Purpose |
|------|---------|
| `Booki/Services/BalanceService.swift` | Derives balances from ledger entries |
| `Booki/Services/LiabilityService.swift` | Calculates payouts and exposure |
| `Booki/Services/GradingService.swift` | Client wrapper for grade/settle edge functions |
| `Booki/Services/ParlayGradingService.swift` | Client-side parlay outcome calculation |
| `Booki/Services/SettlementService.swift` | Period-based settlement reports |
| `Booki/Services/AuditService.swift` | Fetches audit history from Supabase |
| `Booki/Services/PickPresenter.swift` | Maps bet status to display model |

### Models
| File | Purpose |
|------|---------|
| `Booki/Models/Bet.swift` | BetStatus, GradeResult enums + SwiftData model |
| `Booki/Models/LedgerEntry.swift` | EntryType enum + SwiftData model |
| `Booki/Models/AuditEvent.swift` | SwiftData model for audit trail |
