#!/usr/bin/env python3
"""Every table with a POLICY must also ENABLE ROW LEVEL SECURITY.

A policy on a table without RLS is inert and silent. Postgres does not warn,
pg_policies lists it exactly as though it works, and every row stays readable.
markets carried an unenforced policy from migration 011 until 046 — five years
of migrations, and nothing surfaced it.

This reads the migrations rather than the live database, so it catches the
mistake at authoring time. Run: python3 scripts/check-rls.py
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIGRATIONS = os.path.join(ROOT, "supabase", "migrations")

POLICY = re.compile(r"CREATE\s+POLICY\s+\S+\s+ON\s+(?:public\.)?(\w+)", re.I)
ENABLE = re.compile(
    r"ALTER\s+TABLE\s+(?:public\.)?(\w+)\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY", re.I
)


def strip_comments(sql: str) -> str:
    # A commented-out ENABLE must not count as one.
    return re.sub(r"--[^\n]*", "", sql)


def main() -> int:
    with_policy: dict[str, str] = {}
    enabled: set[str] = set()

    for path in sorted(glob.glob(os.path.join(MIGRATIONS, "*.sql"))):
        sql = strip_comments(open(path).read())
        name = os.path.basename(path)
        for m in POLICY.finditer(sql):
            with_policy.setdefault(m.group(1), name)
        for m in ENABLE.finditer(sql):
            enabled.add(m.group(1))

    gaps = sorted(t for t in with_policy if t not in enabled)
    if gaps:
        print(f"RLS: {len(gaps)} table(s) with an UNENFORCED policy\n")
        for t in gaps:
            print(f"  {t}")
            print(f"      policy first created in {with_policy[t]}, but no")
            print(f"      ALTER TABLE {t} ENABLE ROW LEVEL SECURITY anywhere.")
            print(f"      The policy is inert and every row is readable.")
        return 1

    print(f"RLS: clean — all {len(with_policy)} tables with policies also enable RLS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
