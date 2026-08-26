#!/usr/bin/env python3
"""Structural checks on supabase/migrations.

A duplicate migration number is silent and dangerous. Both files sort into the
same position, so which one runs first depends on the filename after the
number, and a runner that tracks applied migrations by NUMBER may apply one and
consider the other done. That is how a stale file scheduling a cron for a
deleted edge function nearly shipped: the number was reused in intent but a
second file was actually created, and nothing complained.

Run: python3 scripts/check-migrations.py
"""
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIGRATIONS = os.path.join(ROOT, "supabase", "migrations")
PATTERN = re.compile(r"^(\d{3})_([a-z0-9_]+)\.sql$")


def main() -> int:
    if not os.path.isdir(MIGRATIONS):
        print("no migrations directory")
        return 0

    files = sorted(f for f in os.listdir(MIGRATIONS) if f.endswith(".sql"))
    problems = []
    by_number = defaultdict(list)

    for name in files:
        m = PATTERN.match(name)
        if not m:
            problems.append(
                (name, "does not match NNN_snake_case.sql — it will sort unpredictably")
            )
            continue
        by_number[int(m.group(1))].append(name)

    for number, names in sorted(by_number.items()):
        if len(names) > 1:
            problems.append(
                (
                    f"{number:03d}",
                    "used by " + ", ".join(names)
                    + " — order between them is undefined and a runner keyed on the "
                      "number may apply only one",
                )
            )

    # Gaps are worth surfacing but are not failures: a migration can be
    # withdrawn before it is ever applied, which is exactly what happened to
    # 041, and renumbering afterwards would be worse than the gap.
    numbers = sorted(by_number)
    gaps = [n for n in range(1, max(numbers) + 1) if n not in by_number] if numbers else []

    if problems:
        print(f"migrations: {len(problems)} problem(s)\n")
        for where, why in problems:
            print(f"  {where}")
            print(f"      {why}")
        return 1

    print(f"migrations: clean — {len(files)} files, numbers unique and well-formed")
    if gaps:
        print("  gaps (not an error): " + ", ".join(f"{g:03d}" for g in gaps))
    return 0


if __name__ == "__main__":
    sys.exit(main())
