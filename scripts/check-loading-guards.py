#!/usr/bin/env python3
"""Count headers must not render a number the data hasn't arrived for yet.

The Events tab showed "0 events" and the full "no events" empty state before
its query returned, then jumped to 97. Two independent causes, and a fix needs
both:

  1. the x-text rendered `filteredEvents.length` with no loading guard, and
  2. `isLoadingEvents` DEFAULTED TO FALSE, so even the guarded list template
     below it (`x-if="!isLoadingEvents"`) was satisfied at first paint.

Cause 2 is the one review misses. A flag that starts false means "loaded", and
every view whose header was already correct (players, player events, player
track, dashboard, player home) starts true. The outliers were the bug.

So this checks both halves:

  A. every isLoading* flag consumed by a view template defaults to true
  B. every x-text that renders <state-array>.length is guarded

Reported as a QA finding on 2026-08-27; the count flash had been visible on
every cold load of the Events tab.
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
JS = ROOT / 'landing' / 'dashboard' / 'dashboard.js'
HTML = ROOT / 'landing' / 'dashboard' / 'index.html'

js = JS.read_text()
lines = HTML.read_text().split('\n')

# Root-level state arrays — `name: [],` at the component's top level — that are
# actually FILLED FROM A QUERY. A `.length` on a loop variable
# (leagueGroup.events, ticket.legs) is already inside rendered data, and an
# array that is only ever set locally (betSlipSelections) legitimately starts
# empty: rendering 0 for it is correct, not a flash.
declared = set(re.findall(r'^\s{8}([A-Za-z_]\w*):\s*\[\s*\],\s*$', js, re.M))
state_arrays = {a for a in declared
                if re.search(r'this\.' + a + r'\s*=[^;\n]*\bdata\b', js)}
flag_defaults = dict(re.findall(r'^\s{8}(isLoading\w*):\s*(true|false),\s*$', js, re.M))

problems = []

# --- A. flags that gate a template must not default to false ----------------
gating = set()
for ln in lines:
    for m in re.finditer(r'(?:template x-if|x-show)="([^"]*)"', ln):
        gating.update(re.findall(r'\b(isLoading\w+)\b', m.group(1)))

# Only flags whose negated guard actually wraps an empty state. Those are the
# ones where a false default is VISIBLE: the view says "nothing here" before it
# has asked. A false default on a flag that merely toggles a spinner is not a
# user-visible defect and is not worth failing a build over.
for flag in sorted(gating):
    if flag_defaults.get(flag) != 'false':
        continue
    for i, ln in enumerate(lines):
        if re.search(r'template x-if="\s*!\s*' + flag + r'\b', ln):
            if 'empty-state' in '\n'.join(lines[i:i + 45]):
                problems.append(
                    f'{flag} defaults to false and gates an empty state '
                    f'(index.html:{i + 1}) — the view says "nothing here" '
                    f'before it has queried')
                break

# --- B. unguarded count headers ---------------------------------------------
XTEXT = re.compile(r'x-text="([^"]*)"')
for i, ln in enumerate(lines, 1):
    for m in XTEXT.finditer(ln):
        expr = m.group(1)
        if 'isLoading' in expr:
            continue
        for arr in re.findall(r'\b(\w+)\.length\b', expr):
            if arr not in state_arrays:
                continue
            # An enclosing template that already gates on the same emptiness is
            # a real guard — e.g. invites count inside x-if="invites.length > 0".
            guarded = False
            for j in range(i - 2, max(0, i - 40), -1):
                prev = lines[j]
                if re.search(r'template x-if="[^"]*isLoading', prev):
                    guarded = True
                    break
                if re.search(rf'template x-if="[^"]*\b{arr}\.length\s*>', prev):
                    guarded = True
                    break
            if not guarded:
                problems.append(
                    f'index.html:{i} renders {arr}.length with no loading guard '
                    f'— shows 0 before the query returns')

if problems:
    print('loading guards: %d problem(s)' % len(problems))
    for p in problems:
        print('  ' + p)
    sys.exit(1)

print('loading guards: clean — %d state arrays, %d gating flags, all guarded'
      % (len(state_arrays), len(gating)))
