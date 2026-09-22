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

resolve_args=()
[ -n "$START_DIR" ] && resolve_args+=(--start-dir "$START_DIR")
resolved_line="$(bash "$SCRIPT_DIR/resolve-engine.sh" "${resolve_args[@]}")"
kind="${resolved_line%% *}"
engine="${resolved_line#* }"

case "$kind" in
  cli)
    # midflight has no --check-config flag; fall back to scripts/check-config.sh
    repo_root="$(dirname "$(dirname "$engine")")"
    if [ -f "$repo_root/scripts/check-config.sh" ]; then
      exec bash "$repo_root/scripts/check-config.sh"
    fi
    printf 'run-check-config: midflight found but scripts/check-config.sh missing\n' >&2
    exit 1
    ;;
  query)
    repo_root="$(dirname "$engine")"
    check_script="$repo_root/check-config.sh"
    if [ -f "$check_script" ]; then
      exec bash "$check_script"
    fi
    printf 'run-check-config: check-config.sh not found near %s\n' "$engine" >&2
    exit 1
    ;;
  *)
    printf 'run-check-config: unexpected engine kind %s\n' "$kind" >&2
    exit 1
    ;;
esac
