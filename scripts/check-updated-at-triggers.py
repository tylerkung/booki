#!/usr/bin/env python3
"""Every table with an updated_at column must have a trigger maintaining it.

WHY THIS EXISTS. `markets` carried an updated_at column from migration 001 and
was the only such table with no trigger — bookies, players, events, bets and
acceptance_policies all got one, markets was missed. Nothing failed loudly. The
column simply meant "when this row was inserted" while every reader assumed
"when this row was last written".

That misreading reached production: the superseded-line guard in the submit
endpoints refuses a market whose updated_at trails the latest write, and with
the column frozen at insert time it refused all 705 outright markets — every
futures bet — while their prices were in fact current.

A missing trigger is invisible in review because the absence is what's wrong.
This makes it visible.
"""
import re
import sys
from pathlib import Path

MIGRATIONS = Path(__file__).resolve().parent.parent / 'supabase' / 'migrations'

# Tables that intentionally have no trigger, with the reason. A row here is a
# decision on the record, not a way to silence the check.
EXEMPT = {
    # Append-only and hash-chained: an UPDATE is blocked by an immutability
    # trigger (migrations 015-019), so updated_at can never drift.
    'ledger_entries': 'immutable, append-only hash chain',
}

# Tables whose trigger is created by a migration that only ALTERs them are found
# automatically; nothing needs listing here.


def main() -> int:
    sql = '\n'.join(p.read_text() for p in sorted(MIGRATIONS.glob('*.sql')))

    # Tables declaring an updated_at column in a CREATE TABLE body.
    with_column = set()
    for m in re.finditer(
        r'CREATE TABLE (?:IF NOT EXISTS )?(?:public\.)?(\w+)\s*\(([^;]*?)\n\);',
        sql, re.S | re.I,
    ):
        table, body = m.group(1), m.group(2)
        if re.search(r'^\s*updated_at\s', body, re.M | re.I):
            with_column.add(table)
    # ALTER TABLE ... ADD COLUMN updated_at counts too.
    for m in re.finditer(
        r'ALTER TABLE (?:public\.)?(\w+)[^;]*ADD COLUMN (?:IF NOT EXISTS )?updated_at',
        sql, re.S | re.I,
    ):
        with_column.add(m.group(1))

    with_trigger = {
        m.group(1)
        for m in re.finditer(
            r'CREATE TRIGGER \w+\s+BEFORE UPDATE ON (?:public\.)?(\w+)', sql, re.I,
        )
    }

    missing = sorted(with_column - with_trigger - set(EXEMPT))
    if missing:
        print('updated_at triggers: MISSING')
        for t in missing:
            print(f'  {t}: has an updated_at column but no BEFORE UPDATE trigger.')
            print('    The column will hold its insert time forever, and any reader')
            print('    treating it as "last written" will be silently wrong.')
        return 1

    covered = len(with_column) - len(set(EXEMPT) & with_column)
    print(f'updated_at triggers: clean — {covered} table(s) covered, '
          f'{len(set(EXEMPT) & with_column)} exempt')
    return 0


if __name__ == '__main__':
    sys.exit(main())
