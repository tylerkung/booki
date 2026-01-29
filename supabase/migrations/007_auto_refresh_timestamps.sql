-- ============================================================================
-- Auto Refresh Timestamp Fields
-- Migration: 007_auto_refresh_timestamps.sql
-- Description: Add timestamp fields to track automatic odds/score refresh
-- ============================================================================

-- ============================================================================
-- ADD AUTO-REFRESH TIMESTAMP COLUMNS TO EVENTS TABLE
-- These columns track when the server last automatically refreshed odds/scores
-- ============================================================================

-- last_auto_odds_refresh: Timestamp when odds were last auto-refreshed from Odds API
ALTER TABLE events
ADD COLUMN IF NOT EXISTS last_auto_odds_refresh TIMESTAMPTZ;

-- last_auto_score_refresh: Timestamp when scores were last auto-refreshed from Odds API
ALTER TABLE events
ADD COLUMN IF NOT EXISTS last_auto_score_refresh TIMESTAMPTZ;

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON COLUMN events.last_auto_odds_refresh IS 'Timestamp when odds were last automatically refreshed by server cron job';
COMMENT ON COLUMN events.last_auto_score_refresh IS 'Timestamp when scores were last automatically refreshed by server cron job';
