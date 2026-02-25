-- Add tier column to bookies table for freemium tier system
ALTER TABLE bookies ADD COLUMN IF NOT EXISTS tier TEXT NOT NULL DEFAULT 'free';
