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
# shellcheck disable=SC2207
resolved=( $(bash "$SCRIPT_DIR/resolve-engine.sh" "${resolve_args[@]}") )
kind="${resolved[0]}"
engine="${resolved[1]}"

if [ "$kind" != "check" ]; then
  printf 'run-check-config: expected check engine, got %s\n' "$kind" >&2
  exit 1
fi

exec bash "$engine" "$@"
