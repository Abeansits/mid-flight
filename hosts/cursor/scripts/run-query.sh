#!/usr/bin/env bash
# Cursor host adapter: resolve engine and run query.
#
# There is no provider=cursor yet, so host=Cursor + provider=cursor circularity does
# not apply. The default provider (often codex) is a fine external consult from
# Cursor. Optional --provider NAME forces a provider when using the CLI or
# when falling back to query.sh (via a temporary HOME config staging).
#
# Usage (mirrors scripts/query.sh / bin/midflight handoff from the skill):
#   run-query.sh <query-file> [consult|implement]
#   run-query.sh <video-file-or-url> video [prompt]
#
# Extra flags (must come before positional args):
#   --provider NAME         force provider
#   --start-dir DIR         start engine walk from DIR (tests / skill scripts)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE_PROVIDER=""
START_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
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
  printf 'Usage: run-query.sh [--provider NAME] <query-file> [mode] [video-prompt]\n' >&2
  exit 2
fi

resolve_args=()
[ -n "$START_DIR" ] && resolve_args+=(--start-dir "$START_DIR")
# Preserve paths that contain spaces (kind is a single token; path is the rest).
resolved_line="$(bash "$SCRIPT_DIR/resolve-engine.sh" "${resolve_args[@]}")"
kind="${resolved_line%% *}"
engine="${resolved_line#* }"

case "$kind" in
  cli)
    cli_args=()
    if [ -n "$FORCE_PROVIDER" ]; then
      cli_args+=(-p "$FORCE_PROVIDER")
    fi
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
    # query.sh reads provider from config; stage a temp config override via HOME
    # when --provider was given. Prefer the CLI path whenever possible; this
    # branch is a fallback. Run as a child (not exec) so EXIT can remove tmp.
    if [ -z "$FORCE_PROVIDER" ]; then
      exec bash "$engine" "$@"
    fi
    tmp_home="$(mktemp -d "${TMPDIR:-/tmp}/midflight-cursor-home.XXXXXX")"
    # shellcheck disable=SC2064
    trap 'rm -rf -- "$tmp_home"' EXIT
    mkdir -p "$tmp_home/.config/mid-flight"
    config_src="${HOME}/.config/mid-flight/config"
    if [ -f "$config_src" ]; then
      grep -v '^provider=' "$config_src" > "$tmp_home/.config/mid-flight/config" || true
    else
      : > "$tmp_home/.config/mid-flight/config"
    fi
    printf 'provider=%s\n' "$FORCE_PROVIDER" >> "$tmp_home/.config/mid-flight/config"
    HOME="$tmp_home" bash "$engine" "$@"
    ;;
  *)
    printf 'run-query: unexpected engine kind %s\n' "$kind" >&2
    exit 1
    ;;
esac
