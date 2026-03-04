-- Migration 029: Add win limit support to players and bookies
-- Win limit caps how much a player can win. When reached, picks are blocked or require approval.
-- Net winnings = -balanceOwed (internal positive = player owes, so negative = player has won)

ALTER TABLE players
  ADD COLUMN IF NOT EXISTS win_limit DECIMAL(15,2) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS win_limit_action TEXT DEFAULT 'block'
    CHECK (win_limit_action IN ('block', 'require_approval'));

ALTER TABLE bookies
  ADD COLUMN IF NOT EXISTS default_win_limit DECIMAL(15,2) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS default_win_limit_action TEXT DEFAULT 'block'
    CHECK (default_win_limit_action IN ('block', 'require_approval'));
