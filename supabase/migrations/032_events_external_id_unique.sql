-- ============================================================================
-- Migration: 032_events_external_id_unique.sql
-- Description: Enforce one event row per provider event id.
--
-- Background: sync_games checked for existing events with an unbounded
-- PostgREST select, which silently truncates at 1000 rows. Everything past the
-- cap looked new and was re-inserted every run, producing 25,133 event rows
-- for 5,986 real games. The application bug is fixed (see _shared/pagination.ts),
-- but nothing at the database level prevented it. This index does.
--
-- PREREQUISITE: duplicates must already be removed, or this index fails to
-- build. The cleanup ran 2026-08-18 (25,134 -> 5,986 rows, 0 duplicates).
--
-- Deliberately NOT a partial index. PostgREST generates a bare
-- `ON CONFLICT (external_id)` for upserts, which cannot infer a partial
-- index's predicate and would error. A plain unique index still permits
-- many NULL external_ids, since Postgres treats NULLs as distinct — so
-- manually created events without a provider id remain possible.
-- ============================================================================

-- Verify before building. If this returns any rows, STOP — the index will fail.
--   SELECT external_id, COUNT(*) FROM events
--   WHERE external_id IS NOT NULL
--   GROUP BY external_id HAVING COUNT(*) > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_events_external_id_unique
    ON events (external_id);

-- ============================================================================
-- VERIFICATION
-- ============================================================================
--   SELECT COUNT(*) AS rows, COUNT(DISTINCT external_id) AS distinct_ids
--   FROM events;               -- both should equal 5,986 immediately after
--
--   \d events                  -- idx_events_external_id_unique present
-- ============================================================================
