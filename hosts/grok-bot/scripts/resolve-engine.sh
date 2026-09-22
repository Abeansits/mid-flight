#!/usr/bin/env bash
# Resolve the MidFlight engine for Grok Bot host adapter.
# Returns "cli <path>" or "query <path>" on stdout, or fails.
#
# Resolution order:
#   1. midflight on PATH → cli
#   2. $MIDFLIGHT_ROOT/bin/midflight → cli
#   3. $MIDFLIGHT_ROOT/scripts/query.sh → query
#   4. walk up from --start-dir to a repo root with scripts/query.sh → query
#
# Usage: resolve-engine.sh [--start-dir DIR]

set -euo pipefail

START_DIR="${PWD}"

while [ $# -gt 0 ]; do
  case "$1" in
    --start-dir)
      START_DIR="${2:-}"
      shift 2
      ;;
    *)
      printf 'resolve-engine: unknown arg %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

# 1. midflight on PATH
if command -v midflight >/dev/null 2>&1; then
  cli="$(command -v midflight)"
  printf 'cli %s\n' "$cli"
  exit 0
fi

# 2. MIDFLIGHT_ROOT/bin/midflight
if [ -n "${MIDFLIGHT_ROOT:-}" ] && [ -x "$MIDFLIGHT_ROOT/bin/midflight" ]; then
  printf 'cli %s\n' "$MIDFLIGHT_ROOT/bin/midflight"
  exit 0
fi

# 3. MIDFLIGHT_ROOT/scripts/query.sh
if [ -n "${MIDFLIGHT_ROOT:-}" ] && [ -f "$MIDFLIGHT_ROOT/scripts/query.sh" ]; then
  printf 'query %s\n' "$MIDFLIGHT_ROOT/scripts/query.sh"
  exit 0
fi

# 4. Walk up from START_DIR to find scripts/query.sh (mid-flight repo root)
walk_dir="$(cd "$START_DIR" && pwd)"
while [ "$walk_dir" != "/" ]; do
  if [ -f "$walk_dir/scripts/query.sh" ] && [ -f "$walk_dir/bin/midflight" ]; then
    printf 'query %s\n' "$walk_dir/scripts/query.sh"
    exit 0
  fi
  walk_dir="$(dirname "$walk_dir")"
done

printf 'resolve-engine: midflight not found. Put midflight on PATH or set MIDFLIGHT_ROOT.\n' >&2
exit 1
