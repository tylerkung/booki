-- Read-only. Bets with more than one active settlement.
-- Active = settlement rows minus reversal rows on that bet.
-- Does not update or delete anything.
--
-- On production this should include the 2026-02-26 picks whose ids start
-- with e4df12ed (76ers ML -124, $5, seq 59 and 51) and 297c5d53
-- (Wolves ML -178, $5, seq 174 and 67). Do not correct those rows.
--
-- A parlay paid twice on two different legs is one row per leg here and
-- will not show. The ticket query below catches that. Rows with a NULL
-- bet_id (the old live parlay insert) are in the third query.

SELECT
    b.id AS bet_id,
    b.ticket_id,
    b.side,
    b.odds,
    b.stake,
    b.status,
    b.grade_result,
    count(*) FILTER (WHERE le.type = 'settlement') AS settlement_rows,
    count(*) FILTER (WHERE le.type = 'reversal') AS reversal_rows,
    count(*) FILTER (WHERE le.type = 'settlement')
        - count(*) FILTER (WHERE le.type = 'reversal') AS active_settlements,
    array_agg(le.seq ORDER BY le.seq) FILTER (WHERE le.type = 'settlement') AS settlement_seqs,
    array_agg(le.amount ORDER BY le.seq) FILTER (WHERE le.type = 'settlement') AS settlement_amounts
FROM ledger_entries le
JOIN bets b ON b.id = le.bet_id
WHERE le.type IN ('settlement', 'reversal')
GROUP BY b.id, b.ticket_id, b.side, b.odds, b.stake, b.status, b.grade_result
HAVING count(*) FILTER (WHERE le.type = 'settlement')
     - count(*) FILTER (WHERE le.type = 'reversal') > 1
ORDER BY b.id;
