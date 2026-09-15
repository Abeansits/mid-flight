#!/usr/bin/env bash
# Skill-local entrypoint. Prefers hosts/codex/scripts when the repo tree is
# intact; otherwise requires midflight on PATH or MIDFLIGHT_ROOT.
# Works when only this skill dir + MIDFLIGHT_ROOT engine are installed:
# circular-guard lives in skill/scripts (bundled) or hosts/codex/scripts.
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

# Circular guard: skill-bundled → host scripts → MIDFLIGHT_ROOT hosts tree.
GUARD=""
if [ -f "$SKILL_SCRIPTS/prefer-non-codex-provider.sh" ]; then
  GUARD="$SKILL_SCRIPTS/prefer-non-codex-provider.sh"
elif [ -n "$HOST_SCRIPTS" ] && [ -f "$HOST_SCRIPTS/prefer-non-codex-provider.sh" ]; then
  GUARD="$HOST_SCRIPTS/prefer-non-codex-provider.sh"
elif [ -n "${MIDFLIGHT_ROOT:-}" ] && [ -f "$MIDFLIGHT_ROOT/hosts/codex/scripts/prefer-non-codex-provider.sh" ]; then
  GUARD="$MIDFLIGHT_ROOT/hosts/codex/scripts/prefer-non-codex-provider.sh"
fi

PROVIDER_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --allow-codex-provider) export MIDFLIGHT_ALLOW_CODEX_PROVIDER=1; shift ;;
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

# Always require allow for explicit --provider codex (even without GUARD).
if [ ${#PROVIDER_ARGS[@]} -ge 2 ] \
  && [ "${PROVIDER_ARGS[1]}" = "codex" ] \
  && [ "${MIDFLIGHT_ALLOW_CODEX_PROVIDER:-}" != "1" ]; then
  printf 'midflight skill: --provider codex requires --allow-codex-provider\n' >&2
  exit 1
fi

if [ ${#PROVIDER_ARGS[@]} -eq 0 ]; then
  if [ -n "$GUARD" ]; then
    provider="$(bash "$GUARD")"
  else
    # Minimal inline guard when no prefer script was installed.
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
  fi
  PROVIDER_ARGS=(-p "$provider")
fi

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

# query.sh has no -p flag: stage provider via a temporary HOME config (same as run-query.sh).
provider="${PROVIDER_ARGS[1]}"
tmp_home="$(mktemp -d "${TMPDIR:-/tmp}/midflight-codex-home.XXXXXX")"
cleanup() { rm -rf "$tmp_home"; }
trap cleanup EXIT
mkdir -p "$tmp_home/.config/mid-flight"
config_src="${HOME}/.config/mid-flight/config"
if [ -f "$config_src" ]; then
  grep -v '^provider=' "$config_src" > "$tmp_home/.config/mid-flight/config" || true
else
  : > "$tmp_home/.config/mid-flight/config"
fi
printf 'provider=%s\n' "$provider" >> "$tmp_home/.config/mid-flight/config"
HOME="$tmp_home" bash "$MIDFLIGHT_ROOT/scripts/query.sh" "$@"
