#!/usr/bin/env bash
# Skill-local entrypoint. Prefers hosts/grok/scripts when the repo tree is
# intact; otherwise requires midflight on PATH or MIDFLIGHT_ROOT.
# Works when only this skill dir + MIDFLIGHT_ROOT engine are installed:
# query.sh has no -p flag, so provider override is staged via a temp HOME config
# (same pattern as the Codex host MIDFLIGHT_ROOT path).
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
    --provider)
      if [ -z "${2:-}" ]; then
        printf 'midflight skill: --provider needs a value\n' >&2
        exit 2
      fi
      PROVIDER_ARGS=(-p "$2")
      shift 2
      ;;
    *) break ;;
  esac
done

invoke_midflight() {
  local mf="$1"
  shift
  local mode="${2:-consult}"
  case "$mode" in
    video)
      local args=("${PROVIDER_ARGS[@]}" --video "$1")
      [ -n "${3:-}" ] && args+=("$3")
      exec bash "$mf" "${args[@]}"
      ;;
    *)
      exec bash "$mf" "${PROVIDER_ARGS[@]}" -m "$mode" -f "$1"
      ;;
  esac
}

# Prefer midflight on PATH, then MIDFLIGHT_ROOT/bin/midflight (both accept -p).
if command -v midflight >/dev/null 2>&1; then
  invoke_midflight "$(command -v midflight)" "$@"
fi

if [ -n "${MIDFLIGHT_ROOT:-}" ] && [ -x "$MIDFLIGHT_ROOT/bin/midflight" ]; then
  invoke_midflight "$MIDFLIGHT_ROOT/bin/midflight" "$@"
fi

# query.sh has no -p flag: stage provider via a temporary HOME config (same as
# hosts/grok/scripts/run-query.sh). If no --provider was given, pass through
# without staging so the engine uses the user's real config.
if [ ${#PROVIDER_ARGS[@]} -eq 0 ]; then
  exec bash "$MIDFLIGHT_ROOT/scripts/query.sh" "$@"
fi

provider="${PROVIDER_ARGS[1]}"
tmp_home="$(mktemp -d "${TMPDIR:-/tmp}/midflight-grok-home.XXXXXX")"
# shellcheck disable=SC2064
trap 'rm -rf -- "$tmp_home"' EXIT
mkdir -p "$tmp_home/.config/mid-flight"
config_src="${HOME}/.config/mid-flight/config"
if [ -f "$config_src" ]; then
  grep -v '^provider=' "$config_src" > "$tmp_home/.config/mid-flight/config" || true
else
  : > "$tmp_home/.config/mid-flight/config"
fi
printf 'provider=%s\n' "$provider" >> "$tmp_home/.config/mid-flight/config"
HOME="$tmp_home" bash "$MIDFLIGHT_ROOT/scripts/query.sh" "$@"
