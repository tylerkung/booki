#!/usr/bin/env bash
# Prove supabase/migrations/068_lock_settlement_rpcs.sql on a throwaway
# local Postgres 17 database.
#
# The fixture matches Supabase's function defaults: EXECUTE is granted to
# anon, authenticated, and service_role by name, and PUBLIC still has the
# built-in EXECUTE grant. Migration 063 is applied first so the five
# functions are the real bodies. 063 revokes PUBLIC on settle_parlay_tx and
# mark_ticket_settled and leaves the named anon grant in place. That is the
# hole.
#
# Connects through the local peer socket as the postgres OS user. It does
# not read SUPABASE_URL, PGHOST, or any hosted credential. Do not point it
# at a remote database.
#
# Usage, from the repo root or anywhere:
#   scripts/test-068-settlement-privileges.sh
#
# Requires PostgreSQL 17 already installed and accepting local connections
# (Ubuntu: sudo pg_ctlcluster 17 main start).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB="booki_068_priv_test"
MIGRATION="$ROOT/supabase/migrations/068_lock_settlement_rpcs.sql"
REVERSAL="$ROOT/supabase/migrations/016_ledger_v2_reversal_rpcs.sql"
PRIOR="$ROOT/supabase/migrations/063_one_active_settlement.sql"
SQL_DIR="$ROOT/scripts/sql"
NIL="'00000000-0000-0000-0000-000000000000'::uuid"

if [[ ! -f "$MIGRATION" || ! -f "$PRIOR" || ! -f "$REVERSAL" ]]; then
    echo "migration not found" >&2
    exit 1
fi

if grep -E -q 'UPDATE[[:space:]]+ledger_entries|DELETE[[:space:]]+FROM[[:space:]]+ledger_entries|INSERT[[:space:]]+INTO[[:space:]]+ledger_entries' "$MIGRATION"; then
    echo "068 must not write ledger_entries" >&2
    exit 1
fi

if grep -E -q 'GRANT EXECUTE .* TO (PUBLIC|anon|authenticated)' "$MIGRATION"; then
    echo "068 must not grant execute to anon, authenticated, or PUBLIC" >&2
    exit 1
fi

if grep -E -q 'ON (TABLES|SEQUENCES)' "$MIGRATION"; then
    echo "068 must not change table or sequence privileges" >&2
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

expect_fail() {
    local label="$1"
    local needle="$2"
    local sql="$3"
    local out code
    set +e
    out=$(run_psql -d "$DB" -v ON_ERROR_STOP=1 <<<"$sql" 2>&1)
    code=$?
    set -e
    if [[ $code -eq 0 ]]; then
        echo "FAIL $label: call was allowed" >&2
        printf '%s\n' "$out" >&2
        exit 1
    fi
    if ! grep -Eq "$needle" <<<"$out"; then
        echo "FAIL $label: expected /$needle/" >&2
        printf '%s\n' "$out" >&2
        exit 1
    fi
    echo "ok $label"
}

expect_ok() {
    local label="$1"
    local needle="$2"
    local sql="$3"
    local out
    out=$(run_psql -d "$DB" -q -v ON_ERROR_STOP=1 -At <<<"$sql" 2>&1)
    if ! grep -Eq "$needle" <<<"$out"; then
        echo "FAIL $label: expected /$needle/" >&2
        printf '%s\n' "$out" >&2
        exit 1
    fi
    echo "ok $label"
}

as_role() {
    local role="$1"
    local jwt="$2"
    local statement="$3"
    cat <<SQL
SET SESSION AUTHORIZATION authenticator;
SET ROLE ${role};
-- Session scope, not transaction-local. psql autocommits each statement,
-- and PostgREST's transaction-local setting is visible for the same reason
-- a session setting is: the function reads it in the call that follows.
SELECT set_config('request.jwt.claim.role', '${jwt}', false);
SELECT set_config('request.jwt.claims', '{"role":"${jwt}"}', false);
${statement}
SQL
}

calls=(
    "settle_bet_tx|public.settle_bet_tx(uuid, uuid, text, text)|SELECT settle_bet_tx(${NIL}, NULL, '068-probe', 'manual');|Bet not found"
    "settle_parlay_tx|public.settle_parlay_tx(uuid, uuid, text, text, numeric, text, jsonb)|SELECT settle_parlay_tx(${NIL}, NULL, '068-probe', 'manual', NULL, NULL, NULL);|No bets found for ticket_id"
    "override_grade_tx|public.override_grade_tx(uuid, uuid, text, text, text)|SELECT override_grade_tx(${NIL}, NULL, 'win', '068 probe', '068-probe');|Bet not found"
    "reverse_settlement_tx|public.reverse_settlement_tx(uuid, uuid, text, text)|SELECT reverse_settlement_tx(${NIL}, NULL, '068 probe', '068-probe');|Bet not found"
    "mark_ticket_settled|public.mark_ticket_settled(uuid, timestamptz)|SELECT mark_ticket_settled(${NIL}, now()); SELECT 'mark_ok';|mark_ok"
)

run_psql -d postgres -c "DROP DATABASE IF EXISTS ${DB} WITH (FORCE);"
run_psql -d postgres -c "CREATE DATABASE ${DB};"

# Prod-like roles and default grants, installed before the functions exist
# so CREATE FUNCTION picks them up the way Supabase does. Roles are
# cluster-wide, so a re-run after a failed test has to tolerate them.
run_psql -d "$DB" -v ON_ERROR_STOP=1 <<'SQL'
DO $roles$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
        CREATE ROLE authenticator NOLOGIN NOINHERIT;
    END IF;
END
$roles$;
GRANT anon, authenticated, service_role TO authenticator;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, authenticator;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
SQL

run_psql -d "$DB" -f "$SQL_DIR/063_fixture.sql"
# 063 replaces settle/override/parlay/mark. reverse_settlement_tx still comes
# from 016, which is the body on a database that has applied the ledger RPCs.
run_psql -d "$DB" -f "$REVERSAL"
run_psql -d "$DB" -f "$PRIOR"

run_psql -d "$DB" -v ON_ERROR_STOP=1 <<'SQL'
DO $roles$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN
        CREATE ROLE supabase_admin NOLOGIN NOINHERIT;
    END IF;
END
$roles$;
GRANT USAGE, CREATE ON SCHEMA public TO supabase_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
CREATE FUNCTION public._068_control() RETURNS integer
    LANGUAGE sql
    AS 'SELECT 1';
SQL

echo
echo "===== prod-like grants, before 068 ====="
run_psql -d "$DB" -c "
SELECT p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_exec
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
       'settle_bet_tx', 'settle_parlay_tx', 'override_grade_tx',
       'reverse_settlement_tx', 'mark_ticket_settled', '_068_control'
   )
 ORDER BY 1;
"

# The hole has to be real before the migration, including on the two
# functions 063 already revoked PUBLIC from.
open_count="$(run_psql -d "$DB" -Atc "
SELECT count(*)
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
       'settle_bet_tx', 'settle_parlay_tx', 'override_grade_tx',
       'reverse_settlement_tx', 'mark_ticket_settled'
   )
   AND has_function_privilege('anon', p.oid, 'EXECUTE')
   AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
")"
if [[ "$open_count" != "5" ]]; then
    echo "setup did not reproduce anon execute on all 5 functions (got $open_count)" >&2
    exit 1
fi

expect_ok "anon can call settle_bet_tx before 068" "Bet not found" \
    "$(as_role anon anon "SELECT settle_bet_tx(${NIL}, NULL, '068-probe', 'manual');")"

ledger_before="$(run_psql -d "$DB" -Atc 'SELECT count(*) FROM ledger_entries')"
bets_before="$(run_psql -d "$DB" -Atc 'SELECT count(*) FROM bets')"

echo
echo "===== apply 068 twice ====="
run_psql -d "$DB" --single-transaction -f "$MIGRATION"
run_psql -d "$DB" -f "$MIGRATION"

verify_sql="$(sed -e '/^--/d' -e 's/;//g' "$SQL_DIR/068_verify.sql")"

echo
echo "===== verify ====="
run_psql -d "$DB" -c "
SELECT count(*) AS bad
  FROM (
${verify_sql}
  ) v
 WHERE anon_exec OR authenticated_exec OR NOT service_role_exec OR NOT guarded;
"

bad="$(run_psql -d "$DB" -Atc "
SELECT count(*)
  FROM (
${verify_sql}
  ) v
 WHERE anon_exec OR authenticated_exec OR NOT service_role_exec OR NOT guarded;
")"
if [[ "$bad" != "0" ]]; then
    echo "verify query failed: $bad function(s) still open or unguarded" >&2
    run_psql -d "$DB" -f "$SQL_DIR/068_verify.sql"
    exit 1
fi
echo "ok verify: anon and authenticated false, service_role true, guard present"

for spec in "${calls[@]}"; do
    IFS='|' read -r name signature statement needle <<<"$spec"
    expect_fail "anon denied $name" "permission denied for function $name" \
        "$(as_role anon anon "$statement")"
    expect_fail "authenticated denied $name" "permission denied for function $name" \
        "$(as_role authenticated authenticated "$statement")"
    expect_ok "service_role runs $name" "$needle" \
        "$(as_role service_role service_role "$statement")"
    expect_ok "postgres runs $name" "$needle" "
        SELECT set_config('request.jwt.claim.role', '', false);
        SELECT set_config('request.jwt.claims', '', false);
        $statement
    "
    run_psql -d "$DB" -c "GRANT EXECUTE ON FUNCTION ${signature} TO anon;"
    expect_fail "guard rejects anon on $name" "settlement RPC requires service_role" \
        "$(as_role anon anon "$statement")"
    run_psql -d "$DB" -c "REVOKE EXECUTE ON FUNCTION ${signature} FROM anon;"
done

expect_ok "control function keeps its anon grant" "^t$" "
    SELECT has_function_privilege('anon', 'public._068_control()', 'EXECUTE');
"
expect_ok "replacing a client function keeps the named anon grant" "^t$" "
    CREATE OR REPLACE FUNCTION public._068_control() RETURNS integer LANGUAGE sql AS 'SELECT 1';
    SELECT has_function_privilege('anon', 'public._068_control()', 'EXECUTE');
"

expect_ok "new postgres function is closed to anon" "^f$" "
    CREATE FUNCTION public._068_probe() RETURNS integer LANGUAGE sql AS 'SELECT 1';
    SELECT has_function_privilege('anon', 'public._068_probe()', 'EXECUTE');
"
expect_ok "new postgres function is closed to authenticated" "^f$" "
    SELECT has_function_privilege('authenticated', 'public._068_probe()', 'EXECUTE');
"
expect_ok "new postgres function stays open to service_role" "^t$" "
    SELECT has_function_privilege('service_role', 'public._068_probe()', 'EXECUTE');
"

expect_ok "new supabase_admin function is closed to anon" "^f$" "
    SET ROLE supabase_admin;
    CREATE FUNCTION public._068_admin_probe() RETURNS integer LANGUAGE sql AS 'SELECT 1';
    RESET ROLE;
    SELECT has_function_privilege('anon', 'public._068_admin_probe()', 'EXECUTE');
"
expect_ok "new supabase_admin function stays open to service_role" "^t$" "
    SELECT has_function_privilege('service_role', 'public._068_admin_probe()', 'EXECUTE');
"

ledger_after="$(run_psql -d "$DB" -Atc 'SELECT count(*) FROM ledger_entries')"
bets_after="$(run_psql -d "$DB" -Atc 'SELECT count(*) FROM bets')"
if [[ "$ledger_before" != "$ledger_after" || "$bets_before" != "$bets_after" ]]; then
    echo "calls changed ledger ($ledger_before -> $ledger_after) or bets ($bets_before -> $bets_after)" >&2
    exit 1
fi
echo "ok no ledger or bet rows written ($ledger_after ledger, $bets_after bets)"

echo
echo "===== rollback, then the hole is back, then 068 again ====="
run_psql -d "$DB" --single-transaction -f "$SQL_DIR/068_rollback.sql"
expect_ok "anon can call settle_bet_tx after rollback" "Bet not found" \
    "$(as_role anon anon "SELECT settle_bet_tx(${NIL}, NULL, '068-probe', 'manual');")"
expect_ok "new function after rollback is executable by anon" "^t$" "
    CREATE FUNCTION public._068_after_rollback() RETURNS integer LANGUAGE sql AS 'SELECT 1';
    SELECT has_function_privilege('anon', 'public._068_after_rollback()', 'EXECUTE');
"

run_psql -d "$DB" -f "$MIGRATION"
expect_fail "anon denied again after re-apply" "permission denied for function settle_bet_tx" \
    "$(as_role anon anon "SELECT settle_bet_tx(${NIL}, NULL, '068-probe', 'manual');")"
expect_ok "service_role still runs after re-apply" "Bet not found" \
    "$(as_role service_role service_role "SELECT settle_bet_tx(${NIL}, NULL, '068-probe', 'manual');")"

run_psql -d postgres -c "DROP DATABASE IF EXISTS ${DB} WITH (FORCE);"
# Roles outlive the database. Drop the ones this script created so a later
# local test is not sharing them. Ignore a role this machine already used.
run_psql -d postgres -v ON_ERROR_STOP=0 -c "
    DROP ROLE IF EXISTS authenticator;
    DROP ROLE IF EXISTS supabase_admin;
    DROP ROLE IF EXISTS anon;
    DROP ROLE IF EXISTS authenticated;
    DROP ROLE IF EXISTS service_role;
" >/dev/null || true
echo
echo "Dropped ${DB}."
echo "ALL CHECKS PASSED"
