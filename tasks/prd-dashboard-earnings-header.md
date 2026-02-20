# PRD: Dashboard Earnings Header

## Introduction

Replace the generic "Analytics" navigation title at the top of the bookie dashboard with a Robinhood-style earnings display. Bookies should immediately see their lifetime P/L as a large, prominent number with a line chart showing their earnings trend over time. This transforms the dashboard from a data tool into a financial command center that answers: **"How much have I made?"**

## Goals

- Show lifetime bookie P/L as the hero metric at the top of the dashboard
- Provide a line chart with switchable time ranges (1W / 1M / 3M / 1Y / ALL)
- Remove the large "Analytics" navigation title to reclaim vertical space
- Maintain the 4 summary cards directly below the earnings section

## User Stories

### US-001: Earnings Hero Number
**Description:** As a bookie, I want to see my total lifetime earnings as a large, prominent number at the top of my dashboard so I instantly know how much I've made.

**Acceptance Criteria:**
- [ ] Remove `.navigationTitle("Analytics")` from AnalyticsDashboardView
- [ ] Add earnings header section at the top of the ScrollView (above summary cards)
- [ ] Display lifetime P/L as a large number using `Theme.font(size: 34, weight: .bold)` or larger
- [ ] P/L is bookie-perspective: positive = bookie profited, negative = bookie lost
- [ ] Color-code the number: positive → `Theme.accent`, negative → `Theme.danger`, zero → `Theme.textPrimary`
- [ ] Show a smaller label above or below: period change (e.g., "+$245.00 (7d)") matching the selected time range, with green/red coloring and up/down arrow indicator
- [ ] Compute P/L from all graded bets using existing `PlayerAttentionService.realizedPL` or equivalent logic aggregated across all players
- [ ] Typecheck passes

### US-002: Earnings Line Chart
**Description:** As a bookie, I want to see a line chart of my earnings over time so I can understand my profit trend.

**Acceptance Criteria:**
- [ ] Add a line chart below the hero number, above the summary cards
- [ ] Chart shows cumulative P/L over time (y-axis = running total, x-axis = time)
- [ ] Use Swift Charts framework (`import Charts`) with `LineMark`
- [ ] Line color: `Theme.accent` when lifetime P/L is positive, `Theme.danger` when negative
- [ ] Chart height approximately 150-180pt, full width with horizontal padding matching cards
- [ ] No visible axis labels or grid lines — clean Robinhood-style (value shown in hero number above)
- [ ] Data points computed by aggregating graded bet results by day
- [ ] Handle empty state: if no graded bets, show flat line at $0
- [ ] Typecheck passes

### US-003: Time Range Selector
**Description:** As a bookie, I want to switch between time ranges so I can see my earnings over different periods.

**Acceptance Criteria:**
- [ ] Add horizontally arranged time range tabs below the chart: 1W, 1M, 3M, 1Y, ALL
- [ ] Tabs styled as small capsules/pills — active tab uses `Theme.accent` text or underline, inactive uses `Theme.textMuted`
- [ ] Default selection is ALL (lifetime view)
- [ ] Switching tabs filters the chart data to the selected range
- [ ] Hero number always shows lifetime P/L (does not change with tab)
- [ ] Period change label updates to match selected range (e.g., "+$245.00 (1M)" when 1M is selected)
- [ ] Chart animates smoothly when switching ranges
- [ ] Typecheck passes

### US-004: P/L Data Service
**Description:** As a developer, I need a method to compute daily cumulative P/L data points for the chart.

**Acceptance Criteria:**
- [ ] Add `dailyCumulativePL(bets:days:)` method to `PlayerAttentionService` (or a new helper)
- [ ] Returns array of `(date: Date, cumulativePL: Decimal)` tuples sorted by date ascending
- [ ] Each data point is the running sum of bookie P/L through that day
- [ ] `days` parameter filters to last N days (0 = all time)
- [ ] Bookie P/L per bet: player win → bookie loses payout, player loss → bookie gains stake (same convention as existing `realizedPL`)
- [ ] Only include graded bets (gradeResult != nil, excluding pushes)
- [ ] Typecheck passes

## Functional Requirements

- FR-1: Hero number displays aggregate lifetime P/L across all players and all graded bets
- FR-2: Line chart uses Swift Charts `LineMark` with cumulative daily P/L data
- FR-3: Time range tabs filter chart data; 5 options: 1W (7 days), 1M (30 days), 3M (90 days), 1Y (365 days), ALL
- FR-4: Period change shows the delta between start and end of the selected range
- FR-5: Chart and hero number update reactively when new bets are graded (via @Query)
- FR-6: No navigation title — the earnings display replaces it

## Non-Goals (Out of Scope)

- Interactive chart scrubbing (drag to see value at specific date) — future enhancement
- Breakdown by player or sport
- Revenue projections or forecasts
- Export or share earnings data

## Design Considerations

- Reference: Robinhood portfolio screen — large number, clean line chart, minimal chrome
- The earnings section + time tabs + chart should feel like one cohesive header block
- Keep vertical space reasonable — chart ~150-180pt so the 4 summary cards are still visible without scrolling on most devices
- Use `Theme.background` for the chart area (no separate card background) to feel integrated, not boxed

## Technical Considerations

- Swift Charts is available iOS 16+ (app targets iOS 17+, so no issue)
- Cumulative P/L computation iterates all graded bets — may need optimization if bet count is very large (>10k). For v1, simple aggregation is fine.
- Chart data can be computed as a `@State` or computed property from `@Query` bets
- Existing `PlayerAttentionService.realizedPL` handles per-player P/L — the new method aggregates across all players

## Open Questions

1. Should the chart area be tappable/scrubbable in a future version?
2. Should we show a "You're up X%" percentage alongside the dollar amount?
