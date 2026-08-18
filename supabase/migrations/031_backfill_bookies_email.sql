-- ============================================================================
-- Migration: 031_backfill_bookies_email.sql
-- Description: Backfill bookies.email from auth.users. The web dashboard's two
--              bookie-creation paths omitted the email column, so nearly every
--              web-created organizer has email NULL. iOS (BookieService.swift)
--              always set it correctly. Both dashboard.js insert sites are
--              fixed alongside this migration.
--
-- auth.users is the source of truth: this syncs stale values too, not just
-- NULLs, so an organizer who changed their login email gets corrected.
-- Safe to re-run.
-- ============================================================================

UPDATE bookies b
SET email = u.email,
    updated_at = NOW()
FROM auth.users u
WHERE u.id = b.auth_user_id
  AND b.email IS DISTINCT FROM u.email;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- Should return 0 rows once the backfill has run:
--   SELECT b.id, b.name, b.email, u.email AS auth_email
--   FROM bookies b JOIN auth.users u ON u.id = b.auth_user_id
--   WHERE b.email IS DISTINCT FROM u.email;
-- ============================================================================
