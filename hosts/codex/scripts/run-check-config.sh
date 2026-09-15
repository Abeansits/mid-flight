#!/usr/bin/env bash
# Codex host adapter: resolve check-config.sh and run it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --start-dir) START_DIR="${2:-}"; shift 2 ;;
    *) break ;;
  esac
done

resolve_args=(--check)
[ -n "$START_DIR" ] && resolve_args+=(--start-dir "$START_DIR")
# Preserve paths that contain spaces (kind is a single token; path is the rest).
resolved_line="$(bash "$SCRIPT_DIR/resolve-engine.sh" "${resolve_args[@]}")"
kind="${resolved_line%% *}"
engine="${resolved_line#* }"

if [ "$kind" != "check" ]; then
  printf 'run-check-config: expected check engine, got %s\n' "$kind" >&2
  exit 1
fi

exec bash "$engine" "$@"
