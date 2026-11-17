#!/usr/bin/env bash
# Prove supabase/migrations/063_one_active_settlement.sql on a throwaway
# local Postgres 17 database.
#
# Connects through the local peer socket as the postgres OS user. It does
# not read SUPABASE_URL, PGHOST, or any hosted credential. Do not point it
# at a remote database.
#
# Usage, from the repo root or anywhere:
#   scripts/test-063-settlement-once.sh
#
# Requires PostgreSQL 17 already installed and accepting local connections
# (Ubuntu: sudo pg_ctlcluster 17 main start).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB="booki_063_settlement_test"
MIGRATION="$ROOT/supabase/migrations/063_one_active_settlement.sql"
SQL_DIR="$ROOT/scripts/sql"

if [[ ! -f "$MIGRATION" ]]; then
    echo "migration not found: $MIGRATION" >&2
    exit 1
fi

if grep -E -q 'UPDATE[[:space:]]+ledger_entries|DELETE[[:space:]]+FROM[[:space:]]+ledger_entries' "$MIGRATION"; then
    echo "migration must not update or delete ledger_entries" >&2
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
    run_psql -d "$DB" -f "$SQL_DIR/063_fixture.sql"
    run_psql -d "$DB" -c "CREATE TABLE ledger_rows_before_063 AS SELECT id, bookie_id, player_id, bet_id, amount, type, description, created_at, prev_hash, entry_hash, seq FROM ledger_entries;"
}

apply_migration() {
    local mode="$1"
    echo
    echo "===== apply 063 (${mode}) ====="
    if [[ "$mode" == "single-transaction" ]]; then
        run_psql -d "$DB" --single-transaction -f "$MIGRATION"
    else
        run_psql -d "$DB" -f "$MIGRATION"
    fi
    echo "apply 063 (${mode}) committed"
}

echo
echo "########## apply twice, then checks ##########"
recreate_db
apply_migration "single-transaction"
apply_migration "autocommit"

echo
echo "===== duplicate-detection query ====="
dupes="$(run_psql -d "$DB" -At -F '|' -f "$SQL_DIR/063_duplicate_settlements.sql")"
echo "$dupes"
echo "$dupes" | grep -q 'e4df12ed-0000-4000-8000-000000000076' || {
    echo "query did not list e4df12ed" >&2
    exit 1
}
echo "$dupes" | grep -q '297c5d53-0000-4000-8000-000000000297' || {
    echo "query did not list 297c5d53" >&2
    exit 1
}
lines="$(echo "$dupes" | grep -c . || true)"
if [[ "$lines" != "2" ]]; then
    echo "expected 2 duplicate bets before the behavior checks, got ${lines}" >&2
    exit 1
fi
echo "PASS duplicate query lists e4df12ed and 297c5d53"

echo
echo "===== behavior checks ====="
run_psql -d "$DB" --single-transaction -f "$SQL_DIR/063_checks.sql"

echo
echo "===== concurrent settle_bet_tx ====="
# The first transaction holds the ticket lock across a sleep. The second
# starts while that lock is held, then must return the same single row.
run_psql -d "$DB" -c "BEGIN; SELECT settle_bet_tx('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'::uuid, NULL, 'concurrent-a', 'auto'); SELECT pg_sleep(2); COMMIT;" >/tmp/063-concurrent-a.out &
sleep 0.4
run_psql -d "$DB" -Atc "SELECT settle_bet_tx('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'::uuid, NULL, 'concurrent-b', 'auto');" >/tmp/063-concurrent-b.out
wait
concurrent_rows="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM ledger_entries WHERE bet_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2' AND type = 'settlement';")"
if [[ "$concurrent_rows" != "1" ]]; then
    echo "concurrent settle posted ${concurrent_rows} ledger rows" >&2
    echo "----- session A -----" >&2
    cat /tmp/063-concurrent-a.out >&2
    echo "----- session B -----" >&2
    cat /tmp/063-concurrent-b.out >&2
    exit 1
fi
if ! grep -q '"success": true' /tmp/063-concurrent-b.out && ! grep -q '"success" : true' /tmp/063-concurrent-b.out; then
    # jsonb spacing varies. Accept either success flag.
    if ! grep -q 'success' /tmp/063-concurrent-b.out; then
        echo "concurrent second call did not return a result" >&2
        cat /tmp/063-concurrent-b.out >&2
        exit 1
    fi
fi
echo "PASS concurrent settle_bet_tx posts one ledger entry"
echo "session B: $(cat /tmp/063-concurrent-b.out)"

echo
echo "===== concurrent settle_parlay_tx ====="
run_psql -d "$DB" -c "BEGIN; SELECT settle_parlay_tx('ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid, NULL, 'auto_settle_parlay_ffffffff-ffff-4fff-8fff-ffffffffffff_v1', 'auto', NULL, NULL, NULL); SELECT pg_sleep(2); COMMIT;" >/tmp/063-parlay-a.out &
sleep 0.4
run_psql -d "$DB" -Atc "SELECT settle_parlay_tx('ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid, NULL, 'auto_settle_parlay_ffffffff-ffff-4fff-8fff-ffffffffffff_v1', 'auto', NULL, NULL, NULL);" >/tmp/063-parlay-b.out
wait
parlay_rows="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM ledger_entries le JOIN bets b ON b.id = le.bet_id WHERE b.ticket_id = 'ffffffff-ffff-4fff-8fff-ffffffffffff' AND le.type = 'settlement';")"
if [[ "$parlay_rows" != "1" ]]; then
    echo "concurrent parlay settle posted ${parlay_rows} ledger rows" >&2
    echo "----- session A -----" >&2
    cat /tmp/063-parlay-a.out >&2
    echo "----- session B -----" >&2
    cat /tmp/063-parlay-b.out >&2
    exit 1
fi
echo "PASS concurrent settle_parlay_tx posts one ledger entry"
echo "session B: $(cat /tmp/063-parlay-b.out)"

echo
echo "===== rollback, then a second insert is possible again ====="
run_psql -d "$DB" -f "$SQL_DIR/063_rollback.sql"
run_psql -d "$DB" -f "$ROOT/supabase/migrations/034_fix_settle_bet_tx_audit_arity.sql"
run_psql -d "$DB" -f "$ROOT/supabase/migrations/016_ledger_v2_reversal_rpcs.sql"
trigger_gone="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM pg_trigger WHERE tgname = 'reject_duplicate_active_settlement' AND NOT tgisinternal;")"
if [[ "$trigger_gone" != "0" ]]; then
    echo "rollback left the trigger in place" >&2
    exit 1
fi
dupes_after="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM ledger_entries WHERE bet_id IN ('e4df12ed-0000-4000-8000-000000000076','297c5d53-0000-4000-8000-000000000297') AND type = 'settlement';")"
if [[ "$dupes_after" != "4" ]]; then
    echo "rollback changed the seeded duplicates (settlement rows ${dupes_after}, expected 4)" >&2
    exit 1
fi
run_psql -d "$DB" -c "INSERT INTO ledger_entries (bookie_id, player_id, bet_id, amount, type, description) VALUES ('22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 5, 'settlement', 'after rollback');"
echo "PASS rollback removes the guard and does not touch the seeded rows"

echo
echo "===== re-apply 063; a further insert is rejected and the duplicates remain ====="
apply_migration "single-transaction"
set +e
run_psql -d "$DB" -c "INSERT INTO ledger_entries (bookie_id, player_id, bet_id, amount, type, description) VALUES ('22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 9, 'settlement', 'third');" >/tmp/063-third.out 2>&1
third_status=$?
set -e
if [[ "$third_status" -eq 0 ]]; then
    echo "re-applied guard allowed a third settlement" >&2
    cat /tmp/063-third.out >&2
    exit 1
fi
if ! grep -q 'active settlement already exists' /tmp/063-third.out; then
    echo "third insert failed for an unexpected reason" >&2
    cat /tmp/063-third.out >&2
    exit 1
fi
dupes_final="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM ledger_entries WHERE bet_id IN ('e4df12ed-0000-4000-8000-000000000076','297c5d53-0000-4000-8000-000000000297') AND type = 'settlement';")"
if [[ "$dupes_final" != "4" ]]; then
    echo "re-apply changed the seeded duplicates" >&2
    exit 1
fi
echo "PASS re-apply rejects a new duplicate and leaves e4df12ed and 297c5d53 untouched"

run_psql -d postgres -c "DROP DATABASE IF EXISTS ${DB} WITH (FORCE);"
echo
echo "Dropped ${DB}."
echo "ALL CHECKS PASSED"
