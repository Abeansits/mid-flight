#!/usr/bin/env bash
# Resolve MidFlight engine entrypoints for the Grok Bot host adapter.
#
# Prints one line: "<kind> <path>"
#   kind=cli   → path is bin/midflight (preferred when on PATH)
#   kind=query → path is scripts/query.sh
#   kind=check → path is scripts/check-config.sh  (only with --check)
#
# Resolution order:
#   1. midflight on PATH — use the CLI for queries; for --check, follow the
#      binary to its install root and use scripts/check-config.sh
#   2. MIDFLIGHT_ROOT (clone or install prefix)
#   3. Walk up from --start-dir / this script looking for the repo layout
#
# Usage:
#   resolve-engine.sh [--check] [--start-dir DIR]
# Env:
#   MIDFLIGHT_ROOT  — install/clone root containing bin/ and scripts/

set -euo pipefail

want_check=false
start_dir=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check) want_check=true; shift ;;
    --start-dir) start_dir="${2:-}"; shift 2 ;;
    -h|--help)
      printf '%s\n' "Usage: resolve-engine.sh [--check] [--start-dir DIR]"
      exit 0
      ;;
    *)
      printf 'resolve-engine: unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

is_engine_root() {
  local root="$1"
  [ -f "$root/scripts/query.sh" ] && [ -f "$root/scripts/check-config.sh" ]
}

emit() {
  printf '%s %s\n' "$1" "$2"
}

emit_from_root() {
  local root="$1"
  if [ "$want_check" = true ]; then
    emit check "$root/scripts/check-config.sh"
  elif [ -f "$root/bin/midflight" ]; then
    emit cli "$root/bin/midflight"
  else
    emit query "$root/scripts/query.sh"
  fi
}

# Resolve a possibly-symlinked midflight binary to its engine root.
root_from_midflight_bin() {
  local source="$1" dir
  while [ -L "$source" ]; do
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    source="$(readlink "$source")"
    [[ "$source" != /* ]] && source="$dir/$source"
  done
  dir="$(cd -P "$(dirname "$source")" && pwd)"
  cd -P "$dir/.." && pwd
}

# 1) midflight on PATH
if command -v midflight >/dev/null 2>&1; then
  mf_bin="$(command -v midflight)"
  if [ "$want_check" = true ]; then
    mf_root="$(root_from_midflight_bin "$mf_bin")"
    if is_engine_root "$mf_root"; then
      emit_from_root "$mf_root"
      exit 0
    fi
    # Fall through to MIDFLIGHT_ROOT / walk-up if the on-PATH binary is a stub.
  else
    emit cli "$mf_bin"
    exit 0
  fi
fi

# 2) MIDFLIGHT_ROOT
if [ -n "${MIDFLIGHT_ROOT:-}" ]; then
  if is_engine_root "$MIDFLIGHT_ROOT"; then
    emit_from_root "$MIDFLIGHT_ROOT"
    exit 0
  fi
  printf 'resolve-engine: MIDFLIGHT_ROOT=%s is missing scripts/query.sh\n' "$MIDFLIGHT_ROOT" >&2
  exit 1
fi

# 3) Walk upward from start_dir (default: this script's directory)
if [ -z "$start_dir" ]; then
  start_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

dir="$start_dir"
while [ -n "$dir" ] && [ "$dir" != "/" ]; do
  if is_engine_root "$dir"; then
    emit_from_root "$dir"
    exit 0
  fi
  parent="$(dirname "$dir")"
  [ "$parent" = "$dir" ] && break
  dir="$parent"
done

printf 'resolve-engine: could not find MidFlight engine.\n' >&2
printf 'Install the CLI on PATH, set MIDFLIGHT_ROOT to a mid-flight checkout, or keep this skill inside the repo tree.\n' >&2
exit 1
