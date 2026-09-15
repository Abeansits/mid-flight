#!/usr/bin/env bash
set -euo pipefail

SKILL_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SKILL_SCRIPTS/.." && pwd)"
HOST_SCRIPTS="$(cd "$SKILL_DIR/../../scripts" 2>/dev/null && pwd || true)"

if [ -n "$HOST_SCRIPTS" ] && [ -f "$HOST_SCRIPTS/run-check-config.sh" ]; then
  exec bash "$HOST_SCRIPTS/run-check-config.sh" --start-dir "$SKILL_DIR" "$@"
fi

if command -v midflight >/dev/null 2>&1; then
  mf_bin="$(command -v midflight)"
  source="$mf_bin"
  while [ -L "$source" ]; do
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    source="$(readlink "$source")"
    [[ "$source" != /* ]] && source="$dir/$source"
  done
  root="$(cd -P "$(dirname "$source")/.." && pwd)"
  if [ -f "$root/scripts/check-config.sh" ]; then
    exec bash "$root/scripts/check-config.sh" "$@"
  fi
fi

if [ -n "${MIDFLIGHT_ROOT:-}" ] && [ -f "$MIDFLIGHT_ROOT/scripts/check-config.sh" ]; then
  exec bash "$MIDFLIGHT_ROOT/scripts/check-config.sh" "$@"
fi

printf 'midflight-check-config: engine not found. Put midflight on PATH or set MIDFLIGHT_ROOT.\n' >&2
exit 1
