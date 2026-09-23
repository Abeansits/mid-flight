#!/usr/bin/env bash
# Grok Bot host adapter: resolve engine and run check-config.
#
# Usage: run-check-config.sh [--start-dir DIR]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --start-dir)
      START_DIR="${2:-}"
      shift 2
      ;;
    *)
      printf 'run-check-config: unknown arg %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

resolve_args=(--check)
[ -n "$START_DIR" ] && resolve_args+=(--start-dir "$START_DIR")
resolved_line="$(bash "$SCRIPT_DIR/resolve-engine.sh" "${resolve_args[@]}")"
kind="${resolved_line%% *}"
engine="${resolved_line#* }"

if [ "$kind" != "check" ]; then
  printf 'run-check-config: expected check kind, got %s\n' "$kind" >&2
  exit 1
fi

exec bash "$engine"
