#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# Check required env vars
if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_SERVICE_KEY:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "Required environment variables:"
  echo "  SUPABASE_URL"
  echo "  SUPABASE_SERVICE_KEY"
  echo "  SUPABASE_ANON_KEY"
  echo ""
  echo "Usage:"
  echo "  export SUPABASE_URL=https://vstfauqufwpdytmvjyfz.supabase.co"
  echo "  export SUPABASE_SERVICE_KEY=<service-role-key>"
  echo "  export SUPABASE_ANON_KEY=<anon-key>"
  echo "  ./run.sh [suite-filter]"
  exit 1
fi

# Install deps if needed
if [ ! -d "node_modules" ]; then
  echo "Installing dependencies..."
  npm install --silent
fi

# Run test suites
echo ""
echo "╔══════════════════════════════════════╗"
echo "║     Booki Launch Stress Tests        ║"
echo "╚══════════════════════════════════════╝"
echo ""

node runner.js "$@"
