#!/usr/bin/env bash
# Prove supabase/migrations/061_enable_rls_agreements_and_idempotency.sql
# on a throwaway local Postgres 17 database.
#
# Connects through the local peer socket as the postgres OS user. It does
# not read SUPABASE_URL, PGHOST, or any hosted credential. Do not point it
# at a remote database.
#
# Usage, from the repo root or anywhere:
#   scripts/test-061-rls.sh
#
# Requires PostgreSQL 17 already installed and accepting local connections
# (Ubuntu: sudo pg_ctlcluster 17 main start).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB="booki_061_rls_test"
MIGRATION="$ROOT/supabase/migrations/061_enable_rls_agreements_and_idempotency.sql"
SQL_DIR="$ROOT/scripts/sql"

if [[ ! -f "$MIGRATION" ]]; then
    echo "migration not found: $MIGRATION" >&2
    exit 1
fi

run_psql() {
    # sudo env_reset drops PGHOST/DATABASE_URL from the caller.
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
    run_psql -d "$DB" -f "$SQL_DIR/061_fixture.sql"
}

show_state() {
    local title="$1"
    echo
    echo "----- ${title} -----"
    run_psql -d "$DB" -c "
        SELECT c.relname, c.relrowsecurity AS rls, c.relforcerowsecurity AS forced,
               c.relacl::text AS acl
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relname IN ('user_agreements', 'idempotency_keys')
         ORDER BY 1;
    "
    run_psql -d "$DB" -c "
        SELECT tablename, policyname, roles::text AS roles, cmd,
               qual, with_check
          FROM pg_policies
         WHERE schemaname = 'public'
           AND tablename IN ('user_agreements', 'idempotency_keys')
         ORDER BY tablename, policyname;
    "
}

apply_migration() {
    local mode="$1"
    echo
    echo "===== apply 061 (${mode}) ====="
    if [[ "$mode" == "single-transaction" ]]; then
        run_psql -d "$DB" --single-transaction -f "$MIGRATION"
    else
        run_psql -d "$DB" -f "$MIGRATION"
    fi
    echo "apply 061 (${mode}) committed"
}

run_checks() {
    local label="$1"
    echo
    echo "===== checks after ${label} ====="
    run_psql -d "$DB" --single-transaction -f "$SQL_DIR/061_checks.sql"
}

# Cycle 1: from the prod shape, apply inside one transaction, then apply
# again the same way. The second apply is the re-run.
echo
echo "########## cycle 1: --single-transaction, then re-run the same way ##########"
recreate_db
show_state "fixture (RLS off, both duplicate policies, seeded rows)"
apply_migration "single-transaction"
apply_migration "single-transaction"
show_state "after two --single-transaction applies"
run_checks "two --single-transaction applies"

# Cycle 2: fresh prod shape, apply with autocommit (one statement at a
# time, which is how the SQL editor runs a script), then re-run that way.
echo
echo "########## cycle 2: autocommit, then re-run the same way ##########"
recreate_db
apply_migration "autocommit"
apply_migration "autocommit"
show_state "after two autocommit applies"
run_checks "two autocommit applies"

echo
echo "===== rollback from the PR ====="
run_psql -d "$DB" -f "$SQL_DIR/061_rollback.sql"
show_state "after rollback"
echo
echo "===== old access restored ====="
run_psql -d "$DB" --single-transaction -f "$SQL_DIR/061_old_access.sql"

run_psql -d postgres -c "DROP DATABASE IF EXISTS ${DB} WITH (FORCE);"
echo
echo "Dropped ${DB}."
echo "ALL CHECKS PASSED"
