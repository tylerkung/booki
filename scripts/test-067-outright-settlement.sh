#!/usr/bin/env bash
# Prove supabase/migrations/067_outright_results.sql on a throwaway
# local Postgres 17 database.
#
# Connects through the local peer socket as the postgres OS user. It does
# not read SUPABASE_URL, PGHOST, or any hosted credential. Do not point it
# at a remote database.
#
# Usage, from the repo root or anywhere:
#   scripts/test-067-outright-settlement.sh
#
# Requires PostgreSQL 17 already installed and accepting local connections
# (Ubuntu: sudo pg_ctlcluster 17 main start).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB="booki_067_outright_test"
MIGRATION="$ROOT/supabase/migrations/067_outright_results.sql"
PRIOR="$ROOT/supabase/migrations/063_one_active_settlement.sql"
SQL_DIR="$ROOT/scripts/sql"

if [[ ! -f "$MIGRATION" || ! -f "$PRIOR" ]]; then
    echo "migration not found" >&2
    exit 1
fi

if grep -E -q 'UPDATE[[:space:]]+ledger_entries|DELETE[[:space:]]+FROM[[:space:]]+ledger_entries|DELETE[[:space:]]+FROM[[:space:]]+bets' "$MIGRATION"; then
    echo "migration must not update or delete ledger_entries or bets" >&2
    exit 1
fi

if grep -q 'market_id' "$MIGRATION"; then
    echo "futures settlement must not read market_id" >&2
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

recreate_db() {
    run_psql -d postgres -c "DROP DATABASE IF EXISTS ${DB} WITH (FORCE);"
    run_psql -d postgres -c "CREATE DATABASE ${DB};"
    run_psql -d "$DB" -f "$SQL_DIR/063_fixture.sql"
    run_psql -d "$DB" --single-transaction -f "$PRIOR"
    run_psql -d "$DB" -f "$SQL_DIR/067_seed.sql"
    # Prod grants EXECUTE to anon and authenticated by name via default
    # privileges. REVOKE FROM PUBLIC alone does not remove those.
    run_psql -d "$DB" -c "DO \$\$ BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
            CREATE ROLE anon NOLOGIN;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
            CREATE ROLE authenticated NOLOGIN;
        END IF;
    END \$\$;"
    run_psql -d "$DB" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, PUBLIC;"
}

echo
echo "===== apply 067 twice on an empty outright_results ====="
recreate_db
run_psql -d "$DB" --single-transaction -f "$MIGRATION"
run_psql -d "$DB" -f "$MIGRATION"
echo "apply 067 twice committed"

echo
echo "===== SQL and TS selection keys agree ====="
cd "$ROOT"
node --experimental-strip-types --input-type=module <<'JS' > /tmp/067-vectors.sql
import { readFileSync } from 'node:fs';
import { outrightSideKey, outrightSelectionMatches } from './supabase/functions/_shared/outright.ts';
const vectors = JSON.parse(readFileSync('./supabase/functions/_shared/outright_match_vectors.json', 'utf8'));
const q = (value) => "'" + String(value).replaceAll("'", "''") + "'";
const lines = ['DO $$ BEGIN'];
for (const vector of vectors) {
  if (outrightSelectionMatches(vector.left, vector.right) !== vector.match) {
    throw new Error('TS vector failed: ' + vector.left);
  }
  lines.push(
    `IF outright_selection_matches(${q(vector.left)}, ${q(vector.right)}) IS DISTINCT FROM ${vector.match ? 'TRUE' : 'FALSE'} THEN RAISE EXCEPTION 'SQL match %', ${q(vector.left)}; END IF;`,
  );
  lines.push(
    `IF outright_side_key(${q(vector.left)}) IS DISTINCT FROM ${q(outrightSideKey(vector.left))} THEN RAISE EXCEPTION 'SQL key % got %', ${q(vector.left)}, outright_side_key(${q(vector.left)}); END IF;`,
  );
}
lines.push('END $$;');
process.stdout.write(lines.join('\n'));
JS
run_psql -d "$DB" -f /tmp/067-vectors.sql
echo "PASS SQL and TS matchers agree on the shared vectors"

echo
echo "===== behavior checks ====="
run_psql -d "$DB" --single-transaction -f "$SQL_DIR/067_checks.sql"
echo "PASS settle, re-run, conflicting winner, void, and the old duplicates"

echo
echo "===== anon and authenticated cannot execute settle_outright_tx ====="
sigs=(
    'settle_outright_tx(uuid, text, boolean, uuid, boolean, boolean)'
    'grade_and_settle_bet_tx(uuid, text, uuid, text)'
    'assert_futures_settler(text)'
    'reverse_outright_tx(uuid, text)'
)
for sig in "${sigs[@]}"; do
    for role in anon authenticated; do
        granted="$(run_psql -d "$DB" -Atc "SELECT has_function_privilege('${role}', '${sig}', 'EXECUTE');")"
        if [[ "$granted" != "f" ]]; then
            echo "${role} can EXECUTE ${sig}" >&2
            exit 1
        fi
    done
done
sig="${sigs[0]}"
set +e
run_psql -d "$DB" -c "SET ROLE anon; SELECT settle_outright_tx('67000000-0000-4000-8000-000000000001'::uuid, 'Golden State Warriors', false, NULL);" >/tmp/067-anon.out 2>&1
anon_status=$?
set -e
if [[ "$anon_status" -eq 0 ]]; then
    echo "anon executed settle_outright_tx" >&2
    cat /tmp/067-anon.out >&2
    exit 1
fi
if ! grep -q 'permission denied' /tmp/067-anon.out; then
    echo "anon was refused for an unexpected reason" >&2
    cat /tmp/067-anon.out >&2
    exit 1
fi
# A leaked GRANT must still be stopped by the in-function guard, and must
# not write a second settlement.
run_psql -d "$DB" -c "GRANT EXECUTE ON FUNCTION ${sig} TO anon;"
set +e
run_psql -d "$DB" -c "SET ROLE anon; SELECT settle_outright_tx('67000000-0000-4000-8000-000000000001'::uuid, 'Boston Celtics', false, NULL);" >/tmp/067-anon-grant.out 2>&1
guard_status=$?
set -e
if [[ "$guard_status" -eq 0 ]]; then
    echo "anon with a leaked GRANT executed settle_outright_tx" >&2
    cat /tmp/067-anon-grant.out >&2
    exit 1
fi
if ! grep -q 'settle_outright_tx is restricted to service_role' /tmp/067-anon-grant.out; then
    echo "in-function guard did not name settle_outright_tx" >&2
    cat /tmp/067-anon-grant.out >&2
    exit 1
fi
run_psql -d "$DB" -c "REVOKE ALL ON FUNCTION ${sig} FROM anon;"
warriors_rows="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM ledger_entries WHERE bet_id = '67000000-0000-4000-8000-000000000010' AND type = 'settlement';")"
if [[ "$warriors_rows" != "1" ]]; then
    echo "anon call changed the Warriors settlement count to ${warriors_rows}" >&2
    exit 1
fi
echo "PASS anon and authenticated lack EXECUTE, and a leaked grant still cannot settle"

echo
echo "===== re-apply 067 after rows exist ====="
run_psql -d "$DB" -f "$MIGRATION"
kept="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM outright_results;")"
paid="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM ledger_entries WHERE bet_id = '67000000-0000-4000-8000-000000000010' AND type = 'settlement';")"
if [[ "$kept" != "3" || "$paid" != "1" ]]; then
    echo "re-apply changed stored results (results ${kept}, warriors rows ${paid})" >&2
    exit 1
fi
echo "PASS re-apply keeps the recorded results and the one Warriors payout"

echo
echo "===== concurrent first settle ====="
run_psql -d "$DB" -c "BEGIN; SELECT settle_outright_tx('67000000-0000-4000-8000-000000000003'::uuid, 'Team A', false, '11111111-1111-4111-8111-111111111111'::uuid); SELECT pg_sleep(2); COMMIT;" >/tmp/067-concurrent-a.out &
sleep 0.4
run_psql -d "$DB" -Atc "SELECT settle_outright_tx('67000000-0000-4000-8000-000000000003'::uuid, 'Team A', false, '11111111-1111-4111-8111-111111111111'::uuid);" >/tmp/067-concurrent-b.out
wait
race_rows="$(run_psql -d "$DB" -Atc "SELECT count(*) FROM ledger_entries WHERE bet_id = '67000000-0000-4000-8000-000000000050' AND type = 'settlement';")"
if [[ "$race_rows" != "1" ]]; then
    echo "concurrent settle posted ${race_rows} ledger rows" >&2
    echo "----- session A -----" >&2
    cat /tmp/067-concurrent-a.out >&2
    echo "----- session B -----" >&2
    cat /tmp/067-concurrent-b.out >&2
    exit 1
fi
if ! grep -q 'success' /tmp/067-concurrent-b.out; then
    echo "concurrent second call did not return a result" >&2
    cat /tmp/067-concurrent-b.out >&2
    exit 1
fi
echo "PASS concurrent settle_outright_tx posts one ledger entry"
echo "session B: $(cat /tmp/067-concurrent-b.out)"

run_psql -d postgres -c "DROP DATABASE IF EXISTS ${DB} WITH (FORCE);"
echo
echo "Dropped ${DB}."
echo "ALL CHECKS PASSED"
