-- Add display_name column to players table
-- Allows bookies to set a custom display name for their members
ALTER TABLE players ADD COLUMN IF NOT EXISTS display_name TEXT DEFAULT NULL;
