-- Read-only. Finds a submit idempotency key whose stored response names one
-- ticket, plus another ticket for the same player, market, stake, and odds
-- created within a few seconds. That second ticket is the one the key race
-- left behind: the key row points at the first ticket only.
--
-- Known production pair (do not update or delete):
--   key 0845800d
--   ticket defc7465 / bet 55c3ae26
--   ticket 51bd1346 / bet 569a7dbd
--
-- A batch of singles shares one key across tickets on purpose. Those tickets
-- are named in the key's response and this query does not list them.
-- Null market_id rows match each other. Require a market so those pairs
-- stay out; the real Colorado pair has market 1050ea8a.

WITH keyed AS (
  SELECT
    ik.key,
    ik.operation,
    (elem->>'id')::uuid AS bet_id
  FROM idempotency_keys ik
  CROSS JOIN LATERAL jsonb_array_elements(
    CASE
      WHEN jsonb_typeof(ik.response::jsonb->'bets') = 'array' THEN ik.response::jsonb->'bets'
      WHEN jsonb_typeof(ik.response::jsonb->'bet') = 'object' THEN jsonb_build_array(ik.response::jsonb->'bet')
      ELSE '[]'::jsonb
    END
  ) AS elem
  WHERE ik.operation IN ('submit_bet', 'submit_bets', 'submit_parlay')
)
SELECT
  k.key,
  k.operation,
  stored.ticket_id AS stored_ticket_id,
  stored.id AS stored_bet_id,
  dup.ticket_id AS duplicate_ticket_id,
  dup.id AS duplicate_bet_id,
  dup.market_id,
  dup.odds,
  dup.stake,
  stored.created_at AS stored_at,
  dup.created_at AS duplicate_at
FROM keyed k
JOIN bets stored ON stored.id = k.bet_id
JOIN bets dup
  ON dup.player_id = stored.player_id
 AND dup.market_id IS NOT DISTINCT FROM stored.market_id
 AND dup.odds = stored.odds
 AND dup.stake = stored.stake
 AND stored.market_id IS NOT NULL
 AND dup.ticket_id <> stored.ticket_id
 AND dup.id <> stored.id
 AND dup.created_at BETWEEN stored.created_at - interval '5 seconds'
                       AND stored.created_at + interval '30 seconds'
ORDER BY k.key, stored.ticket_id, dup.ticket_id;
