#!/usr/bin/env bash
# Skill-local entrypoint for check-config.
set -euo pipefail

SKILL_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SKILL_SCRIPTS/.." && pwd)"
HOST_SCRIPTS=""
if [ -d "$SKILL_DIR/../../scripts" ]; then
  HOST_SCRIPTS="$(cd "$SKILL_DIR/../../scripts" && pwd)"
fi

if [ -n "$HOST_SCRIPTS" ] && [ -f "$HOST_SCRIPTS/run-check-config.sh" ]; then
  exec bash "$HOST_SCRIPTS/run-check-config.sh" --start-dir "$SKILL_DIR"
fi

# Standalone skill install: only PATH / MIDFLIGHT_ROOT remain.
if [ -z "${MIDFLIGHT_ROOT:-}" ] && ! command -v midflight >/dev/null 2>&1; then
  printf 'midflight-check-config: engine not found. Put midflight on PATH or set MIDFLIGHT_ROOT.\n' >&2
  exit 1
fi

# Resolve check-config.sh
if command -v midflight >/dev/null 2>&1; then
  mf="$(command -v midflight)"
  repo_root="$(dirname "$(dirname "$mf")")"
  if [ -f "$repo_root/scripts/check-config.sh" ]; then
    exec bash "$repo_root/scripts/check-config.sh"
  fi
fi

if [ -n "${MIDFLIGHT_ROOT:-}" ] && [ -f "$MIDFLIGHT_ROOT/scripts/check-config.sh" ]; then
  exec bash "$MIDFLIGHT_ROOT/scripts/check-config.sh"
fi

printf 'midflight-check-config: check-config.sh not found\n' >&2
exit 1
