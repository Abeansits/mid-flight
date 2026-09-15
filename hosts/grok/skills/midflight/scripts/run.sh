#!/usr/bin/env bash
# Skill-local entrypoint. Prefers hosts/grok/scripts when the repo tree is
# intact; otherwise requires midflight on PATH or MIDFLIGHT_ROOT.
set -euo pipefail

SKILL_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SKILL_SCRIPTS/.." && pwd)"
HOST_SCRIPTS=""
if [ -d "$SKILL_DIR/../../scripts" ]; then
  HOST_SCRIPTS="$(cd "$SKILL_DIR/../../scripts" && pwd)"
fi

if [ -n "$HOST_SCRIPTS" ] && [ -f "$HOST_SCRIPTS/run-query.sh" ]; then
  exec bash "$HOST_SCRIPTS/run-query.sh" --start-dir "$SKILL_DIR" "$@"
fi

# Standalone skill install: only PATH / MIDFLIGHT_ROOT remain.
if [ -z "${MIDFLIGHT_ROOT:-}" ] && ! command -v midflight >/dev/null 2>&1; then
  printf 'midflight skill: engine not found. Put midflight on PATH or set MIDFLIGHT_ROOT.\n' >&2
  exit 1
fi

PROVIDER_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --provider) PROVIDER_ARGS=(-p "$2"); shift 2 ;;
    *) break ;;
  esac
done

if command -v midflight >/dev/null 2>&1; then
  mode="${2:-consult}"
  case "$mode" in
    video)
      args=("${PROVIDER_ARGS[@]}" --video "$1")
      [ -n "${3:-}" ] && args+=("$3")
      exec midflight "${args[@]}"
      ;;
    *)
      exec midflight "${PROVIDER_ARGS[@]}" -m "$mode" -f "$1"
      ;;
  esac
fi

exec bash "$MIDFLIGHT_ROOT/scripts/query.sh" "$@"
