# PRD: Automated Bet Grading & Auto-Pilot Mode

## Introduction

Implement a streamlined betting experience where bets are **automatically accepted and graded by default**. This "auto-pilot" mode removes friction for casual bookies who just want things to work. Bookies who want more control can opt-in to manual acceptance and/or manual grading.

When a game completes, the system automatically determines if each bet won, lost, or pushed based on the final score and the bet's market type (moneyline, spread, or total).

## Goals

- **Default to auto-pilot**: Bets auto-accepted, auto-graded when games complete
- Support grading for moneyline, spread, and total (over/under) markets
- Minimize API calls through smart batching
- Provide clear win/loss/push status for each bet
- Allow bookies to opt-in to manual control if desired

## Default Behavior (Auto-Pilot)

| Stage | Default (Auto-Pilot) | Opt-In (Manual) |
|-------|---------------------|-----------------|
| Bet Submission | Auto-accepted immediately | Pending → Bookie reviews → Accept/Decline |
| Bet Grading | Auto-graded when game finalizes | Bookie triggers "Grade Bets" manually |

**Why this default?**
- Most casual bookies don't want to manually review every bet
- Reduces friction for both bookie and player
- Players see results faster
- Bookies who want control can easily opt-in

## User Stories

### US-001: Auto-accept bets by default
**Description:** As a player, I want my bets accepted immediately so I don't have to wait for bookie approval.

**Acceptance Criteria:**
- [ ] New bets submitted via `submit_bet` edge function are created with status `accepted` (not `pending`)
- [ ] Skip acceptance policy evaluation for auto-pilot mode
- [ ] Player sees bet as "Accepted" immediately in their Track view
- [ ] Audit event logged for auto-acceptance
- [ ] Typecheck passes

### US-002: Auto-grade bets when events finalize
**Description:** As a bookie, I want bets automatically graded when games complete so I don't have to do it manually.

**Acceptance Criteria:**
- [ ] When `auto_refresh_games` marks an event as `final`, trigger grading for that event's bets
- [ ] Grade all `accepted` bets for the finalized event
- [ ] Update bet status to `won`, `lost`, or `push` based on grading logic
- [ ] Emit audit event for each graded bet
- [ ] Sync graded bets to Supabase automatically
- [ ] Typecheck passes

### US-003: Grade moneyline bets
**Description:** As a system, I need to grade moneyline bets based on the game winner.

**Acceptance Criteria:**
- [ ] Compare home vs away score to determine winner
- [ ] Bet on winning team → status = `won`
- [ ] Bet on losing team → status = `lost`
- [ ] Tie game → status = `push` (stake returned)
- [ ] Typecheck passes

### US-004: Grade spread bets
**Description:** As a system, I need to grade spread bets based on point differential.

**Acceptance Criteria:**
- [ ] Parse spread value from bet's side (e.g., "Lakers -3.5" → -3.5)
- [ ] Calculate: bettor's team score + spread vs opponent score
- [ ] If bettor's adjusted score > opponent → `won`
- [ ] If bettor's adjusted score < opponent → `lost`
- [ ] If exactly equal → `push`
- [ ] Typecheck passes

### US-005: Grade total (over/under) bets
**Description:** As a system, I need to grade over/under bets based on combined score.

**Acceptance Criteria:**
- [ ] Parse total value from bet's side (e.g., "Over 220.5" → 220.5)
- [ ] Calculate: homeScore + awayScore
- [ ] If combined > total and bet is Over → `won`
- [ ] If combined < total and bet is Under → `won`
- [ ] If combined equals total exactly → `push`
- [ ] Typecheck passes

### US-006: Bookie opt-in to manual bet acceptance
**Description:** As a bookie, I want to opt-in to manually reviewing bets if I want more control.

**Acceptance Criteria:**
- [ ] Add `manual_bet_acceptance` boolean to bookie settings (default: false)
- [ ] Settings UI toggle: "Require manual bet approval"
- [ ] When enabled, new bets are created with status `pending`
- [ ] Bookie sees pending bets in "Review Bets" section
- [ ] Acceptance policy rules apply when manual mode is enabled
- [ ] Typecheck passes

### US-007: Bookie opt-in to manual grading
**Description:** As a bookie, I want to opt-in to manually grading bets if I want more control.

**Acceptance Criteria:**
- [ ] Add `manual_bet_grading` boolean to bookie settings (default: false)
- [ ] Settings UI toggle: "Grade bets manually"
- [ ] When enabled, bets stay as `accepted` until bookie triggers grading
- [ ] "Grade Bets" button appears in Settings when manual mode is enabled
- [ ] Shows progress and summary during manual grading
- [ ] Typecheck passes

### US-008: Create grade_bet edge function
**Description:** As a developer, I need a server-side function that grades a single bet.

**Acceptance Criteria:**
- [ ] Create `supabase/functions/grade_bet/index.ts`
- [ ] Accept bet_id, event scores (home_score, away_score)
- [ ] Determine grade result based on market type and scores
- [ ] Update bet status to `won`, `lost`, or `push`
- [ ] Set `grade_result` field with outcome details
- [ ] Emit audit event for grading
- [ ] Return graded bet data
- [ ] Typecheck passes

### US-009: Integrate auto-grading into auto_refresh_games
**Description:** As a developer, I need auto_refresh_games to grade bets when events finalize.

**Acceptance Criteria:**
- [ ] After marking event as `final`, query all `accepted` bets for that event
- [ ] Call grading logic for each bet
- [ ] Update bet statuses in database
- [ ] Log count of bets graded per event
- [ ] Handle grading errors gracefully (don't fail entire refresh)
- [ ] Typecheck passes

## Functional Requirements

- FR-1: Default mode is auto-accept + auto-grade (zero manual intervention)
- FR-2: Grading only processes bets with status = `accepted`
- FR-3: A bet can only be graded once the associated event has final scores
- FR-4: Grading must handle all three market types: moneyline, spread, total
- FR-5: Push results do not affect player balance (stake returned)
- FR-6: Won bets calculate payout based on American odds
- FR-7: Lost bets result in stake forfeited (no payout)
- FR-8: Grading is idempotent (running twice produces same result)
- FR-9: Manual mode settings are per-bookie
- FR-10: Settings sync to Supabase for server-side awareness

## Non-Goals

- No grading of player props (not supported by The Odds API)
- No partial grading (e.g., first half bets)
- No live/in-play bet grading
- No automatic balance adjustments (separate settlement feature)

## Technical Considerations

### Grading Logic Reference

**Moneyline:**
```
winner = homeScore > awayScore ? "home" : (awayScore > homeScore ? "away" : "tie")
if bet.side matches winner → won
if tie → push
else → lost
```

**Spread:**
```
// If bet is on home team with spread of -3.5
adjustedScore = teamScore + spread  // e.g., 100 + (-3.5) = 96.5
if adjustedScore > opponentScore → won
if adjustedScore < opponentScore → lost
if equal → push
```

**Total:**
```
combined = homeScore + awayScore
if bet is Over and combined > total → won
if bet is Under and combined < total → won
if combined == total → push
else → lost
```

### Parsing Market Values
- Spread: Extract number from "Team Name -3.5" or "Team Name +7"
- Total: Extract number from "Over 220.5" or "Under 188"
- Use regex: `/-?\d+\.?\d*/` to extract numeric value

### Database Changes
- Add `manual_bet_acceptance` (boolean, default false) to bookies table
- Add `manual_bet_grading` (boolean, default false) to bookies table
- Add `grade_result` (text, nullable) to bets table for outcome details

### Existing Infrastructure
- `auto_refresh_games` already marks events as `final`
- `Event.homeScore` and `Event.awayScore` fields exist
- `Bet.status` can be 'pending', 'accepted', 'won', 'lost', 'push'
- `grade_bet` edge function exists (may need updates)

## Success Metrics

- Default flow requires zero bookie intervention
- Bets graded within minutes of game completion (via auto-refresh)
- 100% accuracy on grading logic (won/lost/push correctly determined)
- Opt-in settings clearly visible in bookie Settings

## Migration Path

1. Add new columns to bookies table (default false = auto-pilot)
2. Update `submit_bet` to check `manual_bet_acceptance` setting
3. Update `auto_refresh_games` to call grading when events finalize
4. Add Settings UI toggles for manual modes
5. Existing bookies get auto-pilot by default (no disruption)
