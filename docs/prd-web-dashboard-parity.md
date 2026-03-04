# PRD: Web Dashboard Parity

## Overview
Bring the web dashboard (`landing/dashboard/`) to full feature parity with the iOS organizer experience. The web app is an Alpine.js SPA backed by Supabase, and all features must follow the existing patterns (CSS variables, card/table/modal conventions, edge function calls, computed getters).

## Priority Order
1. Events/Games browsing (the biggest gap — organizers need to see tonight's games and odds)
2. Settlement view (core organizer workflow for collecting money)
3. Event Detail + batch grading (manage events, enter scores, grade picks)
4. Dashboard enhancements (attention feed, exposure card, risk watchlist)
5. CSV Export (settlement reports)

## Tech Notes
- All changes are in 3 files: `landing/dashboard/app.html`, `landing/dashboard/dashboard.js`, `landing/dashboard/dashboard.css`
- Follow existing patterns: hash routing, `x-show` view switching, computed getters, `callEdgeFunction()`, toast notifications, shimmer loading, responsive tables
- Supabase JS client already initialized — use `this.supabase.from('table').select()`
- Events table: `id, bookie_id (NULL for shared), name, sport, league, start_time, status, home_team, away_team, final_score, external_id, created_at, updated_at`
- Markets table has odds data linked to events
- CSS variables: `--bg`, `--bg-card`, `--bg-elevated`, `--accent`, `--danger`, `--warning`, `--success`, `--text-primary`, `--text-secondary`, `--text-muted`, `--border`
- Use existing CSS classes: `.card`, `.card-header`, `.card-title`, `.data-table`, `.badge`, `.badge-success/danger/warning/muted`, `.btn`, `.btn-accent/secondary/danger/ghost`, `.chip`, `.filter-bar`, `.stats-grid`, `.stat-tile`, `.empty-state`, `.shimmer`, `.modal-overlay`, `.modal`, `.modal-actions`, `.form-group`
- Edge function call pattern: `await this.callEdgeFunction('name', { ...body, idempotency_key: crypto.randomUUID() })`
- Modal pattern: `showXxxModal` boolean state, `isXxxing` loading state, `xxxError` error state
- All async operations: set `isLoadingXxx = true` → work → set `isLoadingXxx = false`
- Responsive: tables become card layout below 768px via `data-label` attributes on `<td>`
