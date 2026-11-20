#!/usr/bin/env bash
# Prove supabase/migrations/065_submit_idempotency.sql on a throwaway
# local Postgres 17 database.
#
# Connects through the local peer socket as the postgres OS user. It does
# not read SUPABASE_URL, PGHOST, or any hosted credential. Do not point it
# at a remote database.
#
# Usage, from the repo root or anywhere:
#   scripts/test-065-submit-once.sh
#
# Requires PostgreSQL 17 already installed and accepting local connections
# (Ubuntu: sudo pg_ctlcluster 17 main start).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB="booki_065_submit_test"
MIGRATION="$ROOT/supabase/migrations/065_submit_idempotency.sql"
SQL_DIR="$ROOT/scripts/sql"

if [[ ! -f "$MIGRATION" ]]; then
    echo "migration not found: $MIGRATION" >&2
    exit 1
fi

if grep -E -q 'UPDATE[[:space:]]+(bets|idempotency_keys)|DELETE[[:space:]]+FROM[[:space:]]+(bets|idempotency_keys)' "$MIGRATION"; then
    echo "migration must not update or delete bets or idempotency_keys" >&2
    exit 1
fi

run_psql() {
    sudo -u postgres psql -v ON_ERROR_STOP=1 "$@"
}

if ! run_psql -d postgres -Atc 'SELECT 1' >/dev/null; then
    echo "Local Postgres is not accepting peer connections." >&2
    echo "Start it with: sudo pg_ctlcluster 17 main start" >&2
    exit 1
fi

version_num="$(run_psql -d postgres -Atc 'SHOW server_version_num')"
version="$(run_psql -d postgres -Atc 'SHOW server_version')"
if (( version_num < 170000 || version_num >= 180000 )); then
    echo "Expected PostgreSQL 17, server reports: $version ($version_num)" >&2
    exit 1
fi

echo "Local server: PostgreSQL $version"
echo "Database: $DB (created and dropped by this script)"
echo "Migration: $MIGRATION"

recreate_db() {
    run_psql -d postgres -c "DROP DATABASE IF EXISTS ${DB} WITH (FORCE);"
    run_psql -d postgres -c "CREATE DATABASE ${DB};"
    run_psql -d "$DB" -f "$SQL_DIR/065_fixture.sql"
    run_psql -d "$DB" -c "CREATE TABLE bets_before_065 AS SELECT id, ticket_id, player_id, market_id, side, odds, stake, status, created_at FROM bets;"
    run_psql -d "$DB" -c "CREATE TABLE keys_before_065 AS SELECT id, key, operation, response, user_id FROM idempotency_keys;"
}

apply_migration() {
    local mode="$1"
    echo
    echo "===== apply 065 (${mode}) ====="
    if [[ "$mode" == "single-transaction" ]]; then
        run_psql -d "$DB" --single-transaction -f "$MIGRATION"
    else
        run_psql -d "$DB" -f "$MIGRATION"
    fi
    echo "apply 065 (${mode}) committed"
}

echo
echo "########## apply twice, then checks ##########"
recreate_db
apply_migration "single-transaction"
apply_migration "autocommit"

seed_bets="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM bets b JOIN bets_before_065 o ON b.id = o.id WHERE b.ticket_id = o.ticket_id AND b.odds = o.odds AND b.stake = o.stake AND b.created_at = o.created_at AND b.status = o.status;")"
if [[ "$seed_bets" != "2" ]]; then
    echo "migration changed the seeded bets (${seed_bets} still match)" >&2
    exit 1
fi
seed_keys="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM idempotency_keys k JOIN keys_before_065 o ON k.id = o.id WHERE k.key = o.key AND k.response = o.response AND k.user_id = o.user_id;")"
if [[ "$seed_keys" != "1" ]]; then
    echo "migration changed the seeded idempotency key" >&2
    exit 1
fi
echo "PASS seeded Colorado rows are unchanged"

echo
echo "===== duplicate-detection query ====="
dupes="$(run_psql -d "$DB" -At -F '|' -f "$SQL_DIR/065_duplicate_submits.sql")"
echo "$dupes"
echo "$dupes" | grep -q 'defc7465-0000-4000-8000-000000defc74' || {
    echo "query did not list defc7465" >&2
    exit 1
}
echo "$dupes" | grep -q '51bd1346-0000-4000-8000-00000051bd13' || {
    echo "query did not list 51bd1346" >&2
    exit 1
}
echo "$dupes" | grep -q '0845800d-0000-4000-8000-000000084580' || {
    echo "query did not list key 0845800d" >&2
    exit 1
}
lines="$(echo "$dupes" | grep -c . || true)"
if [[ "$lines" != "1" ]]; then
    echo "expected 1 duplicate pair, got ${lines}" >&2
    exit 1
fi
echo "PASS duplicate query lists defc7465 and 51bd1346"

echo
echo "===== behavior checks ====="
run_psql -d "$DB" --single-transaction -f "$SQL_DIR/065_checks.sql"
echo "PASS sequential replay, mismatch, peek, batch, parlay, scope, legacy"

echo
echo "===== concurrent claim_bet_submission ====="
run_psql -d "$DB" -f "$SQL_DIR/065_concurrent_a.sql" >/tmp/065-concurrent-a.out &
sleep 0.4
run_psql -d "$DB" -At -f "$SQL_DIR/065_concurrent_b.sql" >/tmp/065-concurrent-b.out
wait
concurrent_bets="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM bets WHERE idempotency_key = 'test065-concurrent';")"
concurrent_tickets="$(run_psql -d "$DB" -Atc "SELECT count(DISTINCT ticket_id) FROM bets WHERE idempotency_key = 'test065-concurrent';")"
if [[ "$concurrent_bets" != "1" || "$concurrent_tickets" != "1" ]]; then
    echo "concurrent claim posted ${concurrent_bets} bets / ${concurrent_tickets} tickets" >&2
    echo "----- session A -----" >&2
    cat /tmp/065-concurrent-a.out >&2
    echo "----- session B -----" >&2
    cat /tmp/065-concurrent-b.out >&2
    exit 1
fi
if ! grep -q 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa10' /tmp/065-concurrent-b.out; then
    echo "concurrent second call did not return the original ticket" >&2
    cat /tmp/065-concurrent-b.out >&2
    exit 1
fi
if grep -q 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb20' /tmp/065-concurrent-b.out; then
    echo "concurrent second call returned its own ticket id" >&2
    cat /tmp/065-concurrent-b.out >&2
    exit 1
fi
echo "PASS concurrent claim_bet_submission posts one bet"
echo "session B: $(cat /tmp/065-concurrent-b.out)"

echo
echo "===== rollback, then a second insert is possible again ====="
run_psql -d "$DB" -f "$SQL_DIR/065_cleanup_fixtures.sql"
run_psql -d "$DB" -f "$SQL_DIR/065_rollback.sql"
fn_gone="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'claim_bet_submission';")"
if [[ "$fn_gone" != "0" ]]; then
    echo "rollback left claim_bet_submission in place" >&2
    exit 1
fi
seed_after="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM bets WHERE id IN ('55c3ae26-0000-4000-8000-000000055c3a','569a7dbd-0000-4000-8000-000000569a7d');")"
if [[ "$seed_after" != "2" ]]; then
    echo "rollback changed the seeded bets (${seed_after})" >&2
    exit 1
fi
run_psql -d "$DB" -c "INSERT INTO bets (bookie_id, player_id, event_id, ticket_id, market, side, odds, stake, status) VALUES ('22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333','after-rollback','16161616-1616-4161-8161-161616161616','spread','Colorado +3',-110,1,'accepted');"
echo "PASS rollback removes the guard and does not touch the seeded rows"

echo
echo "===== re-apply 065; a second claim is a replay and the duplicate remains ====="
apply_migration "single-transaction"
run_psql -d "$DB" -c "SELECT claim_bet_submission('submit_bets','test065-after','11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333','22222222-2222-4222-8222-222222222222','{\"operation\":\"submit_bets\",\"stake\":\"1.00\"}'::jsonb, jsonb_build_array(jsonb_build_object('event_id','test065-event','ticket_id','17171717-1717-4171-8171-171717171717','market','spread','side','Colorado +3','odds',-110,'stake',1,'status','accepted','is_parlay',false,'parlay_legs',1)), '{}'::jsonb);" >/dev/null
set +e
run_psql -d "$DB" -c "SELECT claim_bet_submission('submit_bets','test065-after','11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333','22222222-2222-4222-8222-222222222222','{\"operation\":\"submit_bets\",\"stake\":\"9.00\"}'::jsonb, jsonb_build_array(jsonb_build_object('event_id','test065-event','ticket_id','18181818-1818-4181-8181-181818181818','market','spread','side','Colorado +3','odds',-110,'stake',9,'status','accepted','is_parlay',false,'parlay_legs',1)), '{}'::jsonb);" >/tmp/065-mismatch.out 2>&1
mismatch_status=$?
set -e
if [[ "$mismatch_status" -eq 0 ]]; then
    echo "re-applied guard accepted a different payload" >&2
    cat /tmp/065-mismatch.out >&2
    exit 1
fi
if ! grep -q 'idempotency_payload_mismatch' /tmp/065-mismatch.out; then
    echo "different payload failed for an unexpected reason" >&2
    cat /tmp/065-mismatch.out >&2
    exit 1
fi
after_count="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM bets WHERE idempotency_key = 'test065-after';")"
if [[ "$after_count" != "1" ]]; then
    echo "mismatch after re-apply wrote ${after_count} bets" >&2
    exit 1
fi
seed_final="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM bets WHERE id IN ('55c3ae26-0000-4000-8000-000000055c3a','569a7dbd-0000-4000-8000-000000569a7d') AND odds = -110 AND stake = 1;")"
if [[ "$seed_final" != "2" ]]; then
    echo "re-apply changed the seeded duplicate" >&2
    exit 1
fi
echo "PASS re-apply replays one ticket, rejects a different payload, and leaves defc7465 and 51bd1346 untouched"

run_psql -d postgres -c "DROP DATABASE IF EXISTS ${DB} WITH (FORCE);"
echo
echo "Dropped ${DB}."
echo "ALL CHECKS PASSED"
