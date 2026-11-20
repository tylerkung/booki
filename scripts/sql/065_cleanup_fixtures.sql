-- Rows the behavior checks inserted. Not part of the rollback. The seeded
-- Colorado pair does not use the test065- prefix and is left in place.
DELETE FROM bets
WHERE event_id LIKE 'test065%'
   OR idempotency_key LIKE 'test065%'
   OR id = '13131313-1313-4131-8131-131313131313';

DELETE FROM idempotency_keys
WHERE key LIKE 'test065%';
