# PRD: Server Authority, Legal Acknowledgment & Operational Safety

## Introduction

This PRD transitions Booki from a feature-complete MVP to a production-safe, legally defensive, operator-grade system. It introduces:

1. **Terms of Service & User Agreement Flow** - Required legal acknowledgment before any betting actions
2. **Server Authority via Edge Functions** - All critical actions (bets, settlements, balances) enforced server-side
3. **Idempotency & Retry Safety** - Prevent duplicate submissions and financial inconsistencies
4. **Audit Trail & Dispute Resolution** - Complete history for corrections and disputes

This hardens critical workflows and sets the foundation for real users.

## Goals

- Make Booki server-authoritative for all critical financial actions
- Require explicit user acknowledgment of Booki's role and limitations before use
- Prevent duplicate or inconsistent financial records via idempotency
- Enable safe dispute resolution with complete audit trails
- Reduce legal, operational, and trust risk

## Non-Goals

- No payments or escrow functionality
- No automatic settlement without bookie action
- No consumer-facing sportsbook behavior
- No live betting or odds trading
- No advanced analytics or growth tooling

---

## User Stories

### Phase 1: Terms of Service & User Agreement

#### US-001: Create User Agreements Database Schema
**Description:** As a developer, I need to store user agreement acceptances so we can track legal acknowledgments.

**Acceptance Criteria:**
- [ ] Create Supabase migration for `user_agreements` table with columns:
  - `id` (UUID, primary key)
  - `user_id` (UUID, references auth.users)
  - `role` (text: 'bookie' | 'player')
  - `version` (text, e.g., '1.0')
  - `accepted_at` (timestamp with time zone)
  - `ip_address` (text, nullable)
  - `user_agent` (text, nullable)
- [ ] Add RLS policy: users can only read their own agreements
- [ ] Add RLS policy: agreements are insert-only (no updates or deletes)
- [ ] Document migration in SUPABASE_MIGRATIONS.md
- [ ] Typecheck passes

---

#### US-002: Create UserAgreement SwiftData Model
**Description:** As a developer, I need a local model to cache agreement status for offline access.

**Acceptance Criteria:**
- [ ] Create `UserAgreement` SwiftData model in Booki/Models/
- [ ] Properties: `id`, `userId`, `role`, `version`, `acceptedAt`
- [ ] Add to SwiftData model container in BookiApp.swift
- [ ] Typecheck passes

---

#### US-003: Create AgreementService for Server Communication
**Description:** As a developer, I need a service to check and submit agreement acceptance to Supabase.

**Acceptance Criteria:**
- [ ] Create `AgreementService.swift` in Booki/Services/
- [ ] Method: `checkAgreementStatus(userId: UUID) async throws -> AgreementStatus` (returns .accepted, .required, .outdated)
- [ ] Method: `submitAgreement(userId: UUID, role: String, version: String) async throws`
- [ ] Current agreement version stored as constant: `currentAgreementVersion = "1.0"`
- [ ] Typecheck passes

---

#### US-004: Create UserAgreementView UI
**Description:** As a user, I need to see and accept the terms of service before using Booki.

**Acceptance Criteria:**
- [ ] Create `UserAgreementView.swift` in Booki/Views/
- [ ] Scrollable text area with agreement summary (see US-005 for content)
- [ ] Checkbox with label: "I have read and agree to the Terms of Service"
- [ ] "View Full Terms" link (opens Safari with terms URL or shows full text sheet)
- [ ] "Continue" button disabled until checkbox is checked
- [ ] Uses Theme colors and styling
- [ ] Typecheck passes

---

#### US-005: Draft Terms of Service Content
**Description:** As a user, I need clear language explaining what Booki is and isn't.

**Acceptance Criteria:**
- [ ] Create `TermsOfService.swift` with static content strings
- [ ] Summary text (shown in UserAgreementView):
```
IMPORTANT: Please read carefully before continuing.

Booki is a record-keeping and bet management tool. By using Booki, you acknowledge and agree that:

• Booki does NOT place, accept, or process bets on your behalf
• Booki does NOT hold, transfer, or process any money or payments
• All financial arrangements between bookies and players occur entirely outside this app
• Booki serves only as an organizational tool to track bets and balances
• You are solely responsible for ensuring your activities comply with all applicable local, state, and federal laws
• Booki makes no representations about the legality of sports betting in your jurisdiction

This app is provided for record-keeping and entertainment purposes only. Booki is not a licensed sportsbook, gambling operator, or financial institution.

By continuing, you confirm that you are at least 18 years old (or the legal age in your jurisdiction) and accept these terms.
```
- [ ] Full terms text (longer legal version with liability disclaimers)
- [ ] Typecheck passes

---

#### US-006: Integrate Agreement into Bookie Signup Flow
**Description:** As a new bookie, I must accept the terms before accessing the app.

**Acceptance Criteria:**
- [ ] After successful auth signup, check agreement status via AgreementService
- [ ] If not accepted, show UserAgreementView before BookieMainView
- [ ] On acceptance, call `AgreementService.submitAgreement()` with role "bookie"
- [ ] Store acceptance locally in SwiftData for offline reference
- [ ] Only after acceptance does user see BookieMainView
- [ ] Typecheck passes

---

#### US-007: Integrate Agreement into Player Claim Flow
**Description:** As a new player claiming an invite, I must accept the terms before accessing the app.

**Acceptance Criteria:**
- [ ] After successful player account creation in PlayerClaimView, check agreement status
- [ ] If not accepted, show UserAgreementView with player-specific context
- [ ] On acceptance, call `AgreementService.submitAgreement()` with role "player"
- [ ] Store acceptance locally
- [ ] Only after acceptance does player see PlayerMainView
- [ ] Typecheck passes

---

#### US-008: Enforce Agreement on App Launch
**Description:** As a returning user, I should be blocked if I haven't accepted the latest terms.

**Acceptance Criteria:**
- [ ] On app launch (in AuthGateView or similar), check agreement status for authenticated users
- [ ] If agreement version is outdated or missing, redirect to UserAgreementView
- [ ] User cannot access any betting features until agreement is current
- [ ] Show appropriate message: "We've updated our Terms of Service. Please review and accept to continue."
- [ ] Typecheck passes

---

### Phase 2: Server Authority & Edge Functions

#### US-009: Set Up Supabase Edge Functions Infrastructure
**Description:** As a developer, I need the Edge Functions directory structure and deployment setup.

**Acceptance Criteria:**
- [ ] Create `supabase/functions/` directory
- [ ] Create `supabase/functions/_shared/` for shared utilities
- [ ] Create shared CORS headers helper in `_shared/cors.ts`
- [ ] Create shared auth helper in `_shared/auth.ts` to validate JWT and extract user
- [ ] Create shared response helpers in `_shared/response.ts`
- [ ] Add Edge Functions documentation to README
- [ ] Document deployment process: `supabase functions deploy`
- [ ] Typecheck passes (Deno)

---

#### US-010: Create submit_bet Edge Function
**Description:** As a player, my bet submissions must be validated and created server-side.

**Acceptance Criteria:**
- [ ] Create `supabase/functions/submit_bet/index.ts`
- [ ] Accepts: `event_id`, `market_id`, `side`, `odds`, `stake`, `idempotency_key`
- [ ] Validates: user is authenticated player, event is not locked, odds are valid
- [ ] Creates bet record with status "pending"
- [ ] Returns created bet object
- [ ] Rejects duplicate `idempotency_key` with original response
- [ ] Typecheck passes (Deno)

---

#### US-011: Create accept_bet Edge Function
**Description:** As a bookie, accepting a bet must be server-authoritative.

**Acceptance Criteria:**
- [ ] Create `supabase/functions/accept_bet/index.ts`
- [ ] Accepts: `bet_id`, `idempotency_key`
- [ ] Validates: user is bookie, bet belongs to bookie's players, bet status is "pending"
- [ ] Updates bet status to "accepted"
- [ ] Returns updated bet object
- [ ] Rejects if bet already accepted/declined/settled
- [ ] Typecheck passes (Deno)

---

#### US-012: Create grade_bet Edge Function
**Description:** As a bookie, grading a bet must be server-authoritative.

**Acceptance Criteria:**
- [ ] Create `supabase/functions/grade_bet/index.ts`
- [ ] Accepts: `bet_id`, `outcome` (win/loss/push/void), `idempotency_key`
- [ ] Validates: user is bookie, bet is accepted, bet not already graded
- [ ] Updates bet with outcome
- [ ] Returns updated bet object
- [ ] Typecheck passes (Deno)

---

#### US-013: Create settle_bet Edge Function
**Description:** As a bookie, settling a bet must atomically update bet status and create ledger entries.

**Acceptance Criteria:**
- [ ] Create `supabase/functions/settle_bet/index.ts`
- [ ] Accepts: `bet_id`, `idempotency_key`
- [ ] Validates: bet is graded, bet not already settled
- [ ] In single transaction:
  - Update bet status to "settled"
  - Create ledger entry for player (win: +payout, loss: -stake, push: 0)
  - Update settlement timestamp
- [ ] Returns settlement result with ledger entry
- [ ] Typecheck passes (Deno)

---

#### US-014: Create adjust_balance Edge Function
**Description:** As a bookie, manual balance adjustments must be server-authoritative with audit trail.

**Acceptance Criteria:**
- [ ] Create `supabase/functions/adjust_balance/index.ts`
- [ ] Accepts: `player_id`, `amount`, `reason`, `idempotency_key`
- [ ] Validates: user is bookie, player belongs to bookie
- [ ] Creates ledger entry with type "adjustment" and reason
- [ ] Returns created ledger entry
- [ ] Typecheck passes (Deno)

---

#### US-015: Update iOS App to Use Edge Functions
**Description:** As a developer, I need to update the iOS services to call Edge Functions instead of direct DB writes.

**Acceptance Criteria:**
- [ ] Create `EdgeFunctionService.swift` in Booki/Services/
- [ ] Generic method: `callFunction<T: Decodable>(name: String, body: Encodable) async throws -> T`
- [ ] Handles auth token injection, error responses, retries
- [ ] Update `BetService` to use `submit_bet` function for new bets
- [ ] Generate `idempotency_key` client-side (UUID) for each request
- [ ] Typecheck passes

---

#### US-016: Update Bookie Grading to Use Edge Functions
**Description:** As a developer, I need to update bookie grading workflow to use server-authoritative functions.

**Acceptance Criteria:**
- [ ] Update `GradingService` to call `grade_bet` and `settle_bet` Edge Functions
- [ ] Remove direct database writes for grading/settlement
- [ ] Handle Edge Function errors gracefully with user feedback
- [ ] Maintain existing UI/UX in GradingView
- [ ] Typecheck passes

---

### Phase 3: Idempotency System

#### US-017: Create Idempotency Keys Database Schema
**Description:** As a developer, I need server-side idempotency tracking to prevent duplicates.

**Acceptance Criteria:**
- [ ] Create Supabase migration for `idempotency_keys` table:
  - `key` (UUID, primary key)
  - `action` (text: submit_bet, accept_bet, grade_bet, settle_bet, adjust_balance)
  - `entity_id` (UUID, nullable - the bet_id or player_id affected)
  - `user_id` (UUID, references auth.users)
  - `response_payload` (JSONB - cached response)
  - `created_at` (timestamp)
- [ ] Add index on (key, action) for fast lookups
- [ ] Add expiry policy: keys older than 24 hours can be cleaned up
- [ ] Document migration
- [ ] Typecheck passes

---

#### US-018: Implement Idempotency in Edge Functions
**Description:** As a developer, all Edge Functions must check and store idempotency keys.

**Acceptance Criteria:**
- [ ] Create `_shared/idempotency.ts` helper
- [ ] Method: `checkIdempotency(key, action)` - returns cached response if exists
- [ ] Method: `storeIdempotency(key, action, entityId, response)` - stores after success
- [ ] All financial Edge Functions use idempotency helper
- [ ] Duplicate requests return original response without side effects
- [ ] Typecheck passes (Deno)

---

#### US-019: iOS Retry Logic with Idempotency
**Description:** As a developer, the iOS app must safely retry failed requests.

**Acceptance Criteria:**
- [ ] `EdgeFunctionService` stores pending request idempotency keys locally
- [ ] On network failure, retry with same idempotency key
- [ ] On success, clear stored key
- [ ] Maximum 3 retries with exponential backoff
- [ ] User sees appropriate loading/retry UI states
- [ ] Typecheck passes

---

### Phase 4: Audit Trail & Dispute Resolution

#### US-020: Create Audit Events Database Schema
**Description:** As a developer, I need a comprehensive audit log for all state changes.

**Acceptance Criteria:**
- [ ] Create Supabase migration for `audit_events` table:
  - `id` (UUID, primary key)
  - `bookie_id` (UUID)
  - `actor_user_id` (UUID - who performed the action)
  - `entity_type` (text: bet, event, settlement, ledger, player)
  - `entity_id` (UUID)
  - `action_type` (text: create, update, grade, settle, reverse, adjust, void)
  - `previous_state` (JSONB, nullable)
  - `new_state` (JSONB)
  - `reason` (text, nullable - required for overrides)
  - `created_at` (timestamp)
- [ ] Add RLS: bookies can only read their own audit events
- [ ] Add index on (bookie_id, entity_type, entity_id) for lookups
- [ ] Document migration
- [ ] Typecheck passes

---

#### US-021: Emit Audit Events from Edge Functions
**Description:** As a developer, all Edge Functions must emit audit events for traceability.

**Acceptance Criteria:**
- [ ] Create `_shared/audit.ts` helper
- [ ] Method: `emitAuditEvent(bookieId, actorId, entityType, entityId, action, prevState, newState, reason)`
- [ ] `submit_bet`: emits "create" event
- [ ] `accept_bet`: emits "update" event with previous/new status
- [ ] `grade_bet`: emits "grade" event with outcome
- [ ] `settle_bet`: emits "settle" event
- [ ] `adjust_balance`: emits "adjust" event with reason
- [ ] Typecheck passes (Deno)

---

#### US-022: Create reverse_settlement Edge Function
**Description:** As a bookie, I need to reverse a settlement when mistakes happen.

**Acceptance Criteria:**
- [ ] Create `supabase/functions/reverse_settlement/index.ts`
- [ ] Accepts: `bet_id`, `reason` (required), `idempotency_key`
- [ ] Validates: bet is settled, user is bookie
- [ ] In single transaction:
  - Update bet status to "graded" (un-settle)
  - Create reversing ledger entry (opposite of original)
  - Emit audit event with reason
- [ ] Returns reversal result
- [ ] Typecheck passes (Deno)

---

#### US-023: Create override_grade Edge Function
**Description:** As a bookie, I need to change a bet's grade when disputes arise.

**Acceptance Criteria:**
- [ ] Create `supabase/functions/override_grade/index.ts`
- [ ] Accepts: `bet_id`, `new_outcome`, `reason` (required), `idempotency_key`
- [ ] Validates: bet exists, user is bookie
- [ ] If bet was settled, automatically reverses settlement first
- [ ] Updates grade to new outcome
- [ ] Emits audit event with previous grade, new grade, and reason
- [ ] Returns updated bet
- [ ] Typecheck passes (Deno)

---

#### US-024: Create AuditService for iOS
**Description:** As a developer, I need a service to fetch audit history for display.

**Acceptance Criteria:**
- [ ] Create `AuditService.swift` in Booki/Services/
- [ ] Method: `fetchAuditHistory(entityType: String, entityId: UUID) async throws -> [AuditEvent]`
- [ ] Create `AuditEvent` model with all fields from schema
- [ ] Typecheck passes

---

#### US-025: Add Bet History View for Bookies
**Description:** As a bookie, I want to see the full history of changes for a bet.

**Acceptance Criteria:**
- [ ] Create `BetHistoryView.swift` in Booki/Views/
- [ ] Shows timeline of all audit events for a bet
- [ ] Each event shows: timestamp, action, actor, reason (if any)
- [ ] For state changes, show before/after values
- [ ] Accessible from bet detail view via "View History" button
- [ ] Uses Theme styling
- [ ] Typecheck passes

---

#### US-026: Add Override/Reverse Actions to Bookie UI
**Description:** As a bookie, I need UI to override grades and reverse settlements.

**Acceptance Criteria:**
- [ ] In TicketDetailView (bookie mode), add "Override" menu for graded/settled bets
- [ ] Override options: Change grade (win/loss/push/void), Reverse settlement
- [ ] Tapping override shows sheet with:
  - Current state
  - New state picker (for grade change)
  - Required "Reason" text field
  - Confirm button
- [ ] Calls appropriate Edge Function on confirm
- [ ] Shows success/error feedback
- [ ] Typecheck passes

---

## Functional Requirements

### Terms of Service
- FR-1: All users must accept Terms of Service before accessing betting features
- FR-2: Agreement acceptance is recorded server-side with timestamp
- FR-3: Users with outdated agreement versions are blocked until re-acceptance
- FR-4: Agreement records are immutable (insert-only)

### Server Authority
- FR-5: Bet submission, acceptance, grading, and settlement MUST go through Edge Functions
- FR-6: Clients cannot directly write to bets, ledger_entries, or settlements tables
- FR-7: Edge Functions validate all business rules before mutations
- FR-8: A bet can only transition forward in state (pending → accepted → graded → settled)
- FR-9: Settlement is atomic: bet status + ledger entry in single transaction

### Idempotency
- FR-10: All financial Edge Functions require an idempotency key
- FR-11: Duplicate requests with same key return original response
- FR-12: Duplicate requests with same key but different payload are rejected
- FR-13: Idempotency keys expire after 24 hours

### Audit Trail
- FR-14: All state changes emit audit events
- FR-15: Audit events capture previous state, new state, actor, and timestamp
- FR-16: Overrides and reversals require a reason
- FR-17: Ledger entries are append-only (corrections create new entries)
- FR-18: Balance can always be recomputed from ledger history

## Technical Considerations

### Edge Functions
- Runtime: Deno (Supabase Edge Functions)
- Auth: JWT validation via Supabase auth helpers
- Database: Direct Postgres connection via supabase-js
- Transactions: Use `supabase.rpc()` for atomic operations or Postgres functions

### RLS Updates
- Remove direct INSERT/UPDATE on `bets` for authenticated users
- Add service_role bypass for Edge Functions
- Keep SELECT policies for reading

### Migration Strategy
1. Deploy Edge Functions
2. Update RLS policies (add service_role bypass)
3. Update iOS app to use Edge Functions
4. Monitor for issues
5. Remove direct write policies after validation

## Success Metrics

- Zero duplicate ledger entries from retries
- No manual database fixes required for disputes
- Bookies can resolve disputes without developer intervention
- 100% of users have accepted current Terms of Service
- All bet state changes have corresponding audit events

## Open Questions

- Should odds be snapshotted at submission or acceptance? (Current: submission)
- How many ToS versions should we retain in history?
- Should players see any audit metadata (e.g., "Grade was corrected")?
- Offline mode: queue Edge Function calls or block actions?
