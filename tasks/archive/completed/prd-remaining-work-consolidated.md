# PRD: Remaining Work - Consolidated

## Introduction

This PRD consolidates all outstanding work from partially completed PRDs. Items are prioritized by impact and organized into focused sprints.

**Source PRDs (archived/superseded):**
- prd-auto-refresh.md → Superseded by prd-automatic-games-sync.md
- prd-odds-results-ingestion.md → Superseded by prd-odds-api-integration.md

**Source PRDs (remaining items extracted):**
- prd-bug-fixes-data-consistency.md
- prd-betting-experience-overhaul.md
- prd-acceptance-rules-engine.md
- prd-parlay-grading-rules.md
- prd-weekly-settlement-workflow.md
- prd-auth-fixes-v1.md
- prd-booki-v3.md

---

## Sprint 1: Critical Bug Fixes ✅ COMPLETE

### US-001: Fix Parlay Stake Display Bug ✅
**Source:** prd-bug-fixes-data-consistency.md US-010
**Status:** FIXED (2026-02-11)

**Files Modified:**
- `Booki/Views/TrackView.swift` (lines 14-21) - Fixed `Ticket.totalStake` to check isParlay
- `Booki/Views/AccountView.swift` (lines 147-159) - Fixed `totalStaked` to group by ticketId

---

## Sprint 2: Auth & Player Management ✅ ALREADY IMPLEMENTED

### US-002: Complete Delete Player Functionality ✅
**Source:** prd-auth-fixes-v1.md US-003
**Status:** Already implemented in PlayerDetailView (lines 766-772, 847-905)

Features verified:
- Delete button in Actions section
- Confirmation dialog with history warning
- Deletes from Supabase and local SwiftData
- Proper error handling

### US-003: Add Player Creation Interstitial ✅
**Source:** prd-auth-fixes-v1.md US-005
**Status:** Already implemented in AddPlayerInterstitialSheet (PlayersListView.swift lines 1315-1445)

Features verified:
- Interstitial appears when tapping "Add Player"
- Two options: "Add Player" and "Purchase Seats"
- "Purchase Seats" shows "Coming Soon" alert
- Consistent Theme styling

---

## Sprint 3: Betting UX Polish (DEFERRED)

### US-004: Odds Change Validation Before Submit
**Source:** prd-betting-experience-overhaul.md US-013
**Priority:** Low (Deferred)
**Status:** NOT IMPLEMENTED

**Description:** Detect if odds changed between selection and submission, prompt user to confirm.

**Acceptance Criteria:**
- [ ] Before submitting bet, re-fetch current market odds
- [ ] If odds differ from bet slip selection, show warning modal
- [ ] Modal shows: "Odds changed from -110 to -115. Continue?"
- [ ] User can accept new odds or cancel submission
- [ ] Auto-update bet slip with new odds if accepted
- [ ] Typecheck passes

### US-005: Optimistic UI Updates
**Source:** prd-betting-experience-overhaul.md US-014
**Priority:** Low (Deferred)
**Status:** NOT IMPLEMENTED

**Description:** Show bet as pending immediately while server confirms.

**Acceptance Criteria:**
- [ ] When bet submitted, immediately show in Track view as "Submitting..."
- [ ] Update status to "Pending" or "Accepted" when server responds
- [ ] If server rejects, remove bet and show error
- [ ] Prevents double-tap submissions
- [ ] Typecheck passes

---

## Sprint 4: Parlay Grading Completion ✅ ALREADY IMPLEMENTED

### US-006: Verify Push/Void Policy Implementation ✅
**Source:** prd-parlay-grading-rules.md US-002, US-009
**Status:** Already implemented in ParlayGradingService.swift

Features verified:
- `ParlayGradingService.calculateParlayOutcome()` implements both policies
- `reduceLegReprice`: Lines 89-103 - filters out void/pushed legs, recalculates with valid legs
- `treatAsPush`: Line 86-87 - any push/void returns `.push` outcome
- Single leg handling: If no valid legs remain, returns push (line 96-98)

### US-007: Parlay Leg Status Display ✅
**Source:** prd-parlay-grading-rules.md US-005
**Status:** Already implemented

Features verified:
- TrackView.swift: `TicketHeaderView` shows "2/3 legs graded" (lines 290-294)
- TrackView.swift: Mini status dots per leg (lines 310-317) with `legStatusColor` helper
- TicketDetailView.swift: `TicketDetailBetRowView` shows per-leg status badge (lines 930-948)

### US-008: Parlay Outcome Summary Display ✅
**Source:** prd-parlay-grading-rules.md US-010
**Status:** Already implemented in TicketDetailView.swift

Features verified:
- `parlayOutcomeSection` (lines 534-562) - Shows "PARLAY OUTCOME" header
- `parlayOutcomeBadge` (lines 565-604) - Large win/loss/push badge with icon
- `parlayCalculationBreakdown` (lines 607-718) - Shows original odds, adjusted odds, stake × odds calculation
- `reducedParlayInfo` (lines 720-747) - "Originally 4 legs, 1 pushed, paid as 3-leg parlay"
- Color-coded badges via `outcomeColor()` helper

---

## Sprint 5: Settlement Workflow Completion ✅ ALREADY IMPLEMENTED

### US-009: Player Settlement Detail View ✅
**Source:** prd-weekly-settlement-workflow.md US-006
**Status:** Already implemented in WeeklySettlementView.swift

Features verified:
- `PlayerSettlementDetailView` (lines 671-1030) - Full breakdown
- `BalanceSummaryCard` shows starting → net → payments → ending flow
- `BettingActivityCard` shows bet count, win/loss/push breakdown
- "Mark as Settled" button (lines 915-928) creates PlayerSettlement record
- Notes field supported (lines 907-913)

### US-010: Quick Payment Recording from Settlement ✅
**Source:** prd-weekly-settlement-workflow.md US-007
**Status:** Already implemented in WeeklySettlementView.swift

Features verified:
- "Record Payment" button in PlayerSettlementDetailView (lines 829-863)
- `QuickPaymentSheet` (lines 1242-1461)
- Amount pre-filled with amount owed (line 1400)
- Full Payment / Partial (50%) quick buttons (lines 1289-1316)
- Creates LedgerEntry with type .paymentLogged (lines 1434-1439)
- Success overlay confirmation

### US-011: Settlement CSV Export ✅
**Source:** prd-weekly-settlement-workflow.md US-009
**Status:** Already implemented in WeeklySettlementView.swift

Features verified:
- "Export" button in toolbar (lines 453-466)
- CSV columns match spec (line 197): Player Name, Starting Balance, Net Results, Payments, Adjustments, Ending Balance, Settled
- Filename: settlement_YYYY-MM-DD.csv (lines 164-169)
- Uses ShareLink for sharing/saving (lines 455-458)

---

## Sprint 6: Acceptance Rules Verification ✅ COMPLETE

### US-012: Verify Policy Evaluation in Edge Functions ✅
**Source:** prd-acceptance-rules-engine.md US-003, US-005
**Priority:** High
**Status:** COMPLETE (2026-02-11)

**Implemented:**
- [x] Event lock check works (submit_bet/index.ts lines 170-179)
- [x] Auto-accept mode based on bookie's `manual_bet_acceptance` setting
- [x] Stake threshold checks (max_stake, require_approval_above)
- [x] New player bet threshold check
- [x] Parlay rules (auto_accept_parlays, parlay_max_legs)
- [x] Policy violations stored in policy_violation_reason column

**Files Modified:**
- `supabase/functions/submit_bet/index.ts` - Added policy fetch and validation (lines 181-236)
- `supabase/functions/submit_parlay/index.ts` - Added policy fetch and parlay-specific validation (lines 202-263)

### US-013: Display Policy Violations in Bets List ✅
**Source:** prd-acceptance-rules-engine.md US-006
**Status:** Already implemented in BetsListView.swift (lines 301-306)

Features verified:
- Shows "Review: [reason]" for pending bets with policy violations
- Styled with Theme.warning color
- Only shown for pending bets with non-empty policyViolationReason

---

## Sprint 7: UI Polish (Deferred)

### US-014: Booki v3 Layout Updates
**Source:** prd-booki-v3.md (various)
**Priority:** Low (Deferred)
**Status:** NOT IMPLEMENTED

**Description:** Various UI polish items from Booki v3 PRD.

**Acceptance Criteria:**
- [ ] Remove redundant review screen from bet submission (US-008)
- [ ] Standardize card background colors (US-010)
- [ ] Other UI consistency improvements as needed
- [ ] Typecheck passes

---

## Summary

| Sprint | Stories | Status | Notes |
|--------|---------|--------|-------|
| 1: Bug Fixes | 1 | ✅ COMPLETE | Fixed parlay stake display |
| 2: Auth & Player | 2 | ✅ COMPLETE | Already implemented |
| 3: Betting UX | 2 | ⏸️ DEFERRED | Low priority, odds validation & optimistic UI |
| 4: Parlay Grading | 3 | ✅ COMPLETE | Already implemented |
| 5: Settlement | 3 | ✅ COMPLETE | Already implemented |
| 6: Acceptance Rules | 2 | ✅ COMPLETE | Full policy evaluation implemented |
| 7: UI Polish | 1 | ⏸️ DEFERRED | Low priority |

**Total: 14 user stories**
- ✅ Complete: 11 stories (Sprints 1, 2, 4, 5, 6)
- ⏸️ Deferred: 3 stories (Sprints 3, 7 - low priority)

## Remaining Work

All actionable work is complete. Only deferred low-priority items remain:
- US-004: Odds change validation before submit
- US-005: Optimistic UI updates
- US-014: Booki v3 layout updates

These can be implemented later as UX enhancements.
