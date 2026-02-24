-- Add allow_futures_parlays setting to bookies table
-- When false, players cannot include outright/futures picks in multi-picks (parlays)
ALTER TABLE bookies ADD COLUMN IF NOT EXISTS allow_futures_parlays boolean NOT NULL DEFAULT true;
