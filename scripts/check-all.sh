#!/usr/bin/env bash
# Every repo invariant check, in one command.
#
# These checks existed individually but nothing ran them, so each only fired
# when someone remembered. Running the set is now one command; each script
# exits non-zero on a finding, and the runner reports all failures rather than
# stopping at the first.
set -uo pipefail
cd "$(dirname "$0")/.."

failed=()
for check in \
    scripts/check-migrations.py \
    scripts/check-rls.py \
    scripts/check-updated-at-triggers.py \
    scripts/check-design-tokens.py \
    scripts/check-contrast.py \
    scripts/check-focus-states.py \
    scripts/check-motion.py
do
    echo "── $(basename "$check")"
    if ! python3 "$check"; then
        failed+=("$(basename "$check")")
    fi
    echo
done

if [ ${#failed[@]} -gt 0 ]; then
    echo "FAILED: ${failed[*]}"
    exit 1
fi
echo "all checks clean"
