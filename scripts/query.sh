#!/bin/bash
# Provider-agnostic query script for MidFlight consultations.
#
# Reads a query file (context + question), wraps it with a system prompt
# optimized for mid-development consultation, and routes to the configured
# provider (Codex, Gemini, OpenCode, or Oz). Response goes to stdout.
#
# Usage: query.sh <query-file-path> [consult|implement]
#        query.sh <video-file-or-url> video [prompt]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPTS_DIR="$PROJECT_ROOT/prompts"

# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=scripts/lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=scripts/lib/prompts.sh
source "$SCRIPT_DIR/lib/prompts.sh"
# shellcheck source=scripts/lib/providers.sh
source "$SCRIPT_DIR/lib/providers.sh"
# shellcheck source=scripts/lib/pipeline.sh
source "$SCRIPT_DIR/lib/pipeline.sh"

main() {
  local start_time
  local response
  local duration

  parse_args "$@"
  log "mode=$MODE"

  init_run_workspace
  trap cleanup_run_workspace EXIT
  RESPONSE_FILE="$RUN_DIR/response.txt"

  # Standard execution pipeline:
  # 1. Load config
  # 2. Resolve provider
  # 3. Stage request assets into a single run workspace
  # 4. Build the final prompt
  # 5. Invoke the provider
  # 6. Validate and print the response
  load_config
  if ! validate_config_state; then
    error_exit \
      "invalid config" \
      "Error: MidFlight config is invalid.
$(format_config_validation_issues)"
  fi
  resolve_provider_for_mode "$MODE"
  ensure_provider_available "$provider"
  load_request_payload
  build_full_prompt
  detach_provider_stdin

  start_time=$SECONDS
  run_provider_query "$provider" "$FULL_PROMPT" "$RESPONSE_FILE" "$GEMINI_INCLUDE_DIR"
  read_response "$RESPONSE_FILE" "$provider"
  response="$RESPONSE_CONTENT"

  duration=$((SECONDS - start_time))
  log "response received (${#response} chars) in ${duration}s"
  printf '%s\n' "$response"
}

main "$@"
