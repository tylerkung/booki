# Booki Supabase Database Schema

This directory contains SQL migrations for the Booki multi-tenant database schema.

## Overview

Booki uses Supabase as its cloud backend with PostgreSQL. The schema is designed for:
- **Multi-tenancy**: All data is isolated by `bookie_id`
- **Row Level Security (RLS)**: Database-level data isolation
- **Sync support**: Works with SwiftData for local-first with cloud sync

## Running Migrations

Run migrations in order via the Supabase SQL Editor:

1. `001_initial_schema.sql` - Creates all tables with indexes
2. `002_rls_policies.sql` - Enables RLS and creates policies (future)

## Schema Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                           auth.users                                │
│                    (Supabase Auth - managed)                        │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               │ auth_user_id
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            bookies                                  │
│  id | auth_user_id | name | email | subscription_status | ...       │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               │ bookie_id (tenant isolation)
          ┌────────────────────┼────────────────────┬─────────────────┐
          │                    │                    │                 │
          ▼                    ▼                    ▼                 ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────────────┐
│     players     │  │     events      │  │ acceptance_     │  │                      │
│  id             │  │  id             │  │ policies        │  │                      │
│  bookie_id      │  │  bookie_id      │  │  id             │  │                      │
│  auth_user_id?  │  │  name           │  │  bookie_id (UK) │  │                      │
│  name           │  │  sport          │  │  max_stake      │  │                      │
│  status         │  │  start_time     │  │  ...            │  │                      │
│  ...            │  │  home_team      │  └─────────────────┘  │                      │
└────────┬────────┘  │  away_team      │                       │                      │
         │           │  ...            │                       │                      │
         │           └─────────────────┘                       │                      │
         │                                                     │                      │
         │ player_id                                           │                      │
         ▼                                                     │                      │
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                    bets                                             │
│  id | bookie_id | player_id | event_id | ticket_id | stake | odds | status | ...    │
└────────────────────────────────────────┬────────────────────────────────────────────┘
                                         │
                                         │ bet_id (optional)
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              ledger_entries                                         │
│  id | bookie_id | player_id | bet_id? | amount | type | description | created_at   │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## Tables

### bookies
Bookie accounts linked to Supabase Auth.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| auth_user_id | UUID | Link to auth.users (unique, required) |
| name | TEXT | Display name |
| email | TEXT | Email address |
| subscription_status | TEXT | 'trial', 'active', 'inactive' |
| created_at | TIMESTAMPTZ | Record creation time |
| updated_at | TIMESTAMPTZ | Last modification time |

### players
Player accounts belonging to a bookie.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| bookie_id | UUID | FK to bookies (tenant isolation) |
| auth_user_id | UUID | Optional link to auth.users for player login |
| name | TEXT | Display name |
| email | TEXT | Email address |
| credit_limit | DECIMAL | Player's credit limit |
| status | TEXT | 'active', 'archived', 'banned' |
| collection_status | TEXT | 'noStatus', 'reminded', 'promised', 'overdue' |
| collection_status_date | TIMESTAMPTZ | When collection status was set |
| promised_payment_date | TIMESTAMPTZ | Date player promised to pay |
| username | TEXT | Optional username for player auth |
| password_hash | TEXT | Optional password hash |
| created_at | TIMESTAMPTZ | Record creation time |
| updated_at | TIMESTAMPTZ | Last modification time |

### events
Sports events that bets can be placed on.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| bookie_id | UUID | FK to bookies (tenant isolation) |
| name | TEXT | Event name/title |
| sport | TEXT | Sport type (NBA, NFL, etc.) |
| league | TEXT | League name |
| start_time | TIMESTAMPTZ | Event start time |
| status | TEXT | 'scheduled', 'live', 'final', 'postponed', 'canceled' |
| home_team | TEXT | Home team name |
| away_team | TEXT | Away team name |
| final_score | TEXT | Final score (after event completes) |
| created_at | TIMESTAMPTZ | Record creation time |
| updated_at | TIMESTAMPTZ | Last modification time |

### bets
All bets placed by players.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| bookie_id | UUID | FK to bookies (tenant isolation) |
| player_id | UUID | FK to players |
| event_id | TEXT | Event identifier (may be external ID) |
| ticket_id | UUID | Groups bets placed together |
| market | TEXT | Market type (spread, moneyline, total) |
| side | TEXT | Bet side (home, away, over, under) |
| odds | INT | American odds format |
| stake | DECIMAL | Wager amount |
| status | TEXT | 'pending', 'accepted', 'declined', 'readyToGrade', 'graded', 'settled', 'void' |
| grade_result | TEXT | 'win', 'loss', 'push' |
| is_parlay | BOOLEAN | Whether this is a parlay bet |
| parlay_legs | INT | Number of legs (1 for singles) |
| policy_violation_reason | TEXT | Why bet was queued for review |
| created_at | TIMESTAMPTZ | Record creation time |
| updated_at | TIMESTAMPTZ | Last modification time |

### ledger_entries
Append-only ledger for tracking all balance changes.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| bookie_id | UUID | FK to bookies (tenant isolation) |
| player_id | UUID | FK to players |
| bet_id | UUID | Optional FK to bets |
| amount | DECIMAL | Transaction amount |
| type | TEXT | 'settlement', 'adjustment', 'paymentLogged', 'reversal' |
| description | TEXT | Human-readable description |
| created_at | TIMESTAMPTZ | Record creation time |

### acceptance_policies
Bookie's acceptance policy configuration. One record per bookie.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| bookie_id | UUID | FK to bookies (unique constraint) |
| max_stake | DECIMAL | Max stake to auto-accept |
| require_approval_above | DECIMAL | Stake requiring manual review |
| auto_accept_enabled | BOOLEAN | Whether auto-accept is on |
| auto_accept_new_players | BOOLEAN | Auto-accept from new players |
| new_player_bet_threshold | INT | Bets needed to be "established" |
| auto_accept_parlays | BOOLEAN | Auto-accept parlay bets |
| parlay_max_legs | INT | Max legs for auto-accepted parlays |
| event_lock_offset_minutes | INT | Minutes before start to lock betting |
| parlay_push_void_policy | TEXT | 'reduceLegReprice' or 'treatAsPush' |
| created_at | TIMESTAMPTZ | Record creation time |
| updated_at | TIMESTAMPTZ | Last modification time |

## Indexes

All tables have indexes on:
- `bookie_id` - Required for efficient tenant isolation queries
- Foreign keys and commonly filtered columns

## Triggers

The `update_updated_at_column()` function automatically sets `updated_at` to `NOW()` on any UPDATE for tables with that column.

## Multi-Tenancy

Every table (except `bookies`) has a `bookie_id` column that:
1. Links the record to its owning bookie
2. Enables Row Level Security policies to isolate data
3. Is indexed for query performance

RLS policies are defined in `002_rls_policies.sql`.
