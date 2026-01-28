-- Migration: 005_bets_accepted_at.sql
-- Description: Add accepted_at column to bets table for tracking when bets are accepted by bookies

-- Add accepted_at column to bets table
ALTER TABLE bets ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;

-- Add comment for documentation
COMMENT ON COLUMN bets.accepted_at IS 'Timestamp when bookie accepted the bet (null if pending)';
