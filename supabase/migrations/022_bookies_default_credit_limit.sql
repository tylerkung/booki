-- Add default_credit_limit column to bookies table
-- Used when new members claim an invite — sets their initial credit limit
ALTER TABLE bookies
  ADD COLUMN IF NOT EXISTS default_credit_limit NUMERIC DEFAULT 1000;
