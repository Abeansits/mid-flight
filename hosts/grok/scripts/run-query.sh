#!/usr/bin/env bash
# Grok Build host adapter: resolve engine, apply circular-provider guard, run query.
#
# Usage (mirrors scripts/query.sh / bin/midflight handoff from the skill):
#   run-query.sh <query-file> [consult|implement]
#   run-query.sh <video-file-or-url> video [prompt]
#
# Extra flags (must come before positional args):
#   --allow-grok-provider   allow provider=grok on the Grok host
#   --provider NAME         force provider (implies allow when NAME=grok only via flag)
#   --start-dir DIR         start engine walk from DIR (tests / skill scripts)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOW_GROK=false
FORCE_PROVIDER=""
START_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --allow-grok-provider) ALLOW_GROK=true; shift ;;
    --provider)
      FORCE_PROVIDER="${2:-}"
      [ -n "$FORCE_PROVIDER" ] || { printf 'run-query: --provider needs a value\n' >&2; exit 2; }
      shift 2
      ;;
    --start-dir)
      START_DIR="${2:-}"
      shift 2
      ;;
    --) shift; break ;;
    -*)
      printf 'run-query: unknown flag %s\n' "$1" >&2
      exit 2
      ;;
    *) break ;;
  esac
done

if [ $# -lt 1 ]; then
  printf 'Usage: run-query.sh [--allow-grok-provider] [--provider NAME] <query-file> [mode] [video-prompt]\n' >&2
  exit 2
fi

resolve_args=()
[ -n "$START_DIR" ] && resolve_args+=(--start-dir "$START_DIR")
# Preserve paths that contain spaces (kind is a single token; path is the rest).
resolved_line="$(bash "$SCRIPT_DIR/resolve-engine.sh" "${resolve_args[@]}")"
kind="${resolved_line%% *}"
engine="${resolved_line#* }"

if [ "$ALLOW_GROK" = true ]; then
  export MIDFLIGHT_ALLOW_GROK_PROVIDER=1
fi

if [ -n "$FORCE_PROVIDER" ]; then
  force="$FORCE_PROVIDER"
  [ "$force" = "grok-build" ] && force="grok"
  if [ "$force" = "grok" ] && [ "${MIDFLIGHT_ALLOW_GROK_PROVIDER:-}" != "1" ]; then
    printf 'run-query: --provider grok on Grok host requires --allow-grok-provider or MIDFLIGHT_ALLOW_GROK_PROVIDER=1\n' >&2
    exit 1
  fi
  provider="$FORCE_PROVIDER"
  [ "$provider" = "grok-build" ] && provider="grok"
else
  provider="$(bash "$SCRIPT_DIR/prefer-non-grok-provider.sh")"
fi

case "$kind" in
  cli)
    cli_args=(-p "$provider")
    mode="${2:-consult}"
    case "$mode" in
      video)
        cli_args+=(--video "$1")
        if [ -n "${3:-}" ]; then
          cli_args+=("$3")
        fi
        ;;
      consult|implement)
        cli_args+=(-m "$mode" -f "$1")
        ;;
      *)
        cli_args+=(-m consult -f "$1")
        ;;
    esac
    exec bash "$engine" "${cli_args[@]}"
    ;;
  query)
    # query.sh reads provider from config; stage a temp config override via HOME.
    # Prefer the CLI path whenever possible; this branch is a fallback.
    # Run as a child (not exec) so the EXIT trap can remove tmp_home.
    tmp_home="$(mktemp -d "${TMPDIR:-/tmp}/midflight-grok-home.XXXXXX")"
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
    HOME="$tmp_home" bash "$engine" "$@"
    ;;
  *)
    printf 'run-query: unexpected engine kind %s\n' "$kind" >&2
    exit 1
    ;;
esac
