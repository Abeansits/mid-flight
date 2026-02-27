#!/bin/bash
# Provider-agnostic query script for MidFlight consultations.
#
# Reads a query file (context + question), wraps it with a system prompt
# optimized for mid-development consultation, and routes to the configured
# provider (Codex or Gemini). Response goes to stdout.
#
# Usage: query.sh <query-file-path>

set -euo pipefail

log() { echo "[mid-flight] $*" >&2; }

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [ $# -lt 1 ] || [ -z "$1" ]; then
  log "error: missing query file path"
  echo "Error: No query file provided. Usage: query.sh <query-file-path>"
  exit 1
fi

query_file="$1"

if [ ! -f "$query_file" ]; then
  log "error: query file not found: $query_file"
  echo "Error: Query file not found: $query_file"
  exit 1
fi

query_content=$(cat "$query_file")

if [ -z "$query_content" ]; then
  log "error: query file is empty: $query_file"
  echo "Error: Query file is empty."
  exit 1
fi

# ---------------------------------------------------------------------------
# Config loading — same pattern as pre-flight for user familiarity
# ---------------------------------------------------------------------------
config_file="${HOME}/.config/mid-flight/config"
provider="codex"
codex_model="gpt-5.3-codex"
codex_reasoning_effort="high"
gemini_model="gemini-2.5-pro"

if [ -f "$config_file" ]; then
  val=$(grep '^provider=' "$config_file" | cut -d= -f2- | tr -d '[:space:]')
  [ -n "$val" ] && provider="$val"

  val=$(grep '^codex_model=' "$config_file" | cut -d= -f2- | tr -d '[:space:]')
  [ -n "$val" ] && codex_model="$val"
  val=$(grep '^codex_reasoning_effort=' "$config_file" | cut -d= -f2- | tr -d '[:space:]')
  [ -n "$val" ] && codex_reasoning_effort="$val"
  val=$(grep '^gemini_model=' "$config_file" | cut -d= -f2- | tr -d '[:space:]')
  [ -n "$val" ] && gemini_model="$val"

  log "config loaded: provider=$provider"
else
  log "no config file found at $config_file, using defaults"
fi

# ---------------------------------------------------------------------------
# System prompt for mid-development consultation
# ---------------------------------------------------------------------------
SYSTEM_PROMPT='You are a senior engineer being consulted mid-development. Another engineer (an AI assistant) is working on a task and needs your perspective.

Be direct and concise:
- If you see a clear issue, say so immediately
- If the approach looks sound, confirm briefly and suggest next steps
- If there are multiple valid paths, lay out the tradeoffs in bullets
- Don'"'"'t rehash what they already know — add new signal only'

# ---------------------------------------------------------------------------
# Provider functions
# ---------------------------------------------------------------------------
query_codex() {
  local full_prompt="$1"
  local output_file="$2"

  codex exec \
    --model "$codex_model" \
    -c "model_reasoning_effort=\"$codex_reasoning_effort\"" \
    --full-auto \
    --ephemeral \
    --skip-git-repo-check \
    -o "$output_file" \
    "$full_prompt" \
    2>&1 | while IFS= read -r line; do log "codex: $line"; done
}

query_gemini() {
  local full_prompt="$1"
  local output_file="$2"

  gemini \
    -p "$full_prompt" \
    -m "$gemini_model" \
    --sandbox \
    --output-format text \
    > "$output_file" \
    2> >(while IFS= read -r line; do log "gemini: $line"; done)
}

# ---------------------------------------------------------------------------
# Build the full prompt (system prompt + query content)
# ---------------------------------------------------------------------------
full_prompt="${SYSTEM_PROMPT}

---

${query_content}"

# ---------------------------------------------------------------------------
# Provider routing
# ---------------------------------------------------------------------------
log "sending query to $provider (${#query_content} chars)..."

response_file=$(mktemp /tmp/midflight-response-XXXXXX.txt)
trap 'rm -f "$response_file"' EXIT

case "$provider" in
  codex)
    if ! query_codex "$full_prompt" "$response_file"; then
      log "codex exec failed"
      echo "Error: Codex query failed. Make sure the Codex CLI is installed and authenticated."
      exit 1
    fi
    ;;
  gemini)
    if ! query_gemini "$full_prompt" "$response_file"; then
      log "gemini exec failed"
      echo "Error: Gemini query failed. Make sure the Gemini CLI is installed and authenticated."
      exit 1
    fi
    ;;
  *)
    log "unknown provider: $provider"
    echo "Error: Unknown provider '$provider'. Supported: codex, gemini. Check ~/.config/mid-flight/config"
    exit 1
    ;;
esac

response=$(cat "$response_file" 2>/dev/null || echo "")

if [ -z "$response" ]; then
  log "$provider returned empty response"
  echo "Error: $provider returned an empty response. Try again or switch providers in ~/.config/mid-flight/config"
  exit 1
fi

log "response received (${#response} chars)"
echo "$response"
