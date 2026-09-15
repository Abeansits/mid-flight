#!/usr/bin/env bash
# Skill-local entrypoint. Prefers hosts/codex/scripts when the repo tree is
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

# Re-resolve via a temporary copy of the shared scripts is unnecessary —
# call midflight / query directly with the circular guard if we can find it.
GUARD=""
if [ -n "${MIDFLIGHT_ROOT:-}" ] && [ -f "$MIDFLIGHT_ROOT/hosts/codex/scripts/prefer-non-codex-provider.sh" ]; then
  GUARD="$MIDFLIGHT_ROOT/hosts/codex/scripts/prefer-non-codex-provider.sh"
fi

PROVIDER_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --allow-codex-provider) export MIDFLIGHT_ALLOW_CODEX_PROVIDER=1; shift ;;
    --provider) PROVIDER_ARGS=(-p "$2"); shift 2 ;;
    *) break ;;
  esac
done

if [ -n "$GUARD" ]; then
  if [ ${#PROVIDER_ARGS[@]} -eq 0 ]; then
    provider="$(bash "$GUARD")"
    PROVIDER_ARGS=(-p "$provider")
  elif [ "${PROVIDER_ARGS[1]}" = "codex" ] && [ "${MIDFLIGHT_ALLOW_CODEX_PROVIDER:-}" != "1" ]; then
    printf 'midflight skill: --provider codex requires --allow-codex-provider\n' >&2
    exit 1
  fi
elif [ ${#PROVIDER_ARGS[@]} -eq 0 ]; then
  # Minimal inline guard when shared scripts were not installed.
  provider="codex"
  cfg="${HOME}/.config/mid-flight/config"
  if [ -f "$cfg" ]; then
    v="$(grep '^provider=' "$cfg" | cut -d= -f2- | tr -d '[:space:]' || true)"
    [ -n "$v" ] && provider="$v"
  fi
  [ "$provider" = "antigravity" ] && provider="agy"
  if [ "$provider" = "codex" ] && [ "${MIDFLIGHT_ALLOW_CODEX_PROVIDER:-}" != "1" ]; then
    pick=""
    for c in agy opencode oz gemini; do
      command -v "$c" >/dev/null 2>&1 && { pick="$c"; break; }
    done
    if [ -z "$pick" ]; then
      printf 'midflight skill: refused circular Codex→Codex (no alternate provider on PATH).\n' >&2
      exit 1
    fi
    printf 'midflight skill: host=Codex provider=codex → using %s (set MIDFLIGHT_ALLOW_CODEX_PROVIDER=1 to force).\n' "$pick" >&2
    provider="$pick"
  fi
  PROVIDER_ARGS=(-p "$provider")
fi

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