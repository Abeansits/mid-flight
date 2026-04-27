#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=scripts/lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"

report_provider_status() {
  local provider_name="$1"
  local label="$2"
  local required_level="$3"

  if command -v "$provider_name" >/dev/null 2>&1; then
    printf '[ok] %s: %s\n' "$label" "$(command -v "$provider_name")"
    return 0
  fi

  case "$required_level" in
    required)
      printf '[error] %s: not found in PATH\n' "$label"
      return 1
      ;;
    recommended)
      printf '[warn] %s: not found in PATH\n' "$label"
      return 0
      ;;
    *)
      printf '[info] %s: not found in PATH\n' "$label"
      return 0
      ;;
  esac
}

main() {
  local config_file
  local status=0
  local issue

  config_file="$(config_file_path)"

  printf 'MidFlight config check\n'
  printf 'Config file: %s\n' "$config_file"

  load_config

  if validate_config_state; then
    printf '[ok] Config syntax and values look valid\n'
  else
    status=1
    printf '[error] Config validation failed\n'

    for issue in "${CONFIG_VALIDATION_ISSUES[@]}"; do
      printf '  - %s\n' "$issue"
    done
  fi

  printf 'Active provider: %s\n' "$provider"

  if ! report_provider_status "$provider" "Configured provider ($provider)" "required"; then
    status=1
  fi

  if ! report_provider_status "gemini" "Gemini (required for video mode)" "recommended"; then
    status=1
  fi

  report_provider_status "codex" "Codex (optional alternate provider)" "optional" || true
  report_provider_status "opencode" "OpenCode (optional alternate provider)" "optional" || true
  report_provider_status "oz" "Oz (optional alternate provider)" "optional" || true

  if [ "$status" -eq 0 ]; then
    printf 'PASS: MidFlight config looks good\n'
  else
    printf 'FAIL: MidFlight config needs attention\n'
    exit 1
  fi
}

main "$@"
