#!/bin/bash
# Provider-agnostic query script for MidFlight consultations.
#
# Reads a query file (context + question), wraps it with a system prompt
# optimized for mid-development consultation, and routes to the configured
# provider (Codex or Gemini). Response goes to stdout.
#
# Usage: query.sh <query-file-path> [consult|implement]
#        query.sh <video-file-or-url> video [prompt]

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
mode="${2:-consult}"
case "$mode" in
  consult|implement|video) ;;
  *) log "unknown mode '$mode', defaulting to consult"; mode="consult" ;;
esac

DEFAULT_VIDEO_PROMPT='Provide a comprehensive scene-by-scene breakdown of this video. Organize the analysis into a Markdown table with the following columns:

1. Timestamp: Approximate start and end time of the scene or cut.
2. Visual Narrative: Action, characters, setting, lighting, and color palette.
3. Text & Graphics: Any on-screen text, logos, CTAs, lower thirds, or supers.
4. Cinematography & Editing: Shot types (CU, Wide, POV), camera movement, and transitions.
5. Audio & Soundscape: Music, SFX, ambient sound, dialogue, or voiceover.
6. Emotional Beat: The intended mood or emotional shift in this segment.

After the table, provide:
- A brief summary of the visual symbolism and how color grading supports the storytelling.
- If this is an advertisement: evaluate messaging clarity, call-to-action effectiveness, and brand consistency.'

if [ "$mode" = "video" ]; then
  # --- Video mode: arg1 is a video file or URL, arg3 is optional prompt ---
  video_source="$query_file"
  video_prompt="${3:-$DEFAULT_VIDEO_PROMPT}"

  # Detect URL vs local file
  if [[ "$video_source" =~ ^https?:// ]]; then
    video_is_url=true
    log "video source: URL"
  else
    video_is_url=false

    if [ ! -f "$video_source" ]; then
      log "error: video file not found: $video_source"
      echo "Error: Video file not found: $video_source"
      exit 1
    fi

    # Gemini CLI has a 20MB inline file size limit for local files
    file_size=$(stat -f%z "$video_source" 2>/dev/null || stat -c%s "$video_source" 2>/dev/null || echo "")
    if [ -z "$file_size" ] || [ "$file_size" -eq 0 ]; then
      log "error: could not determine file size: $video_source"
      echo "Error: Could not determine file size for: $video_source"
      exit 1
    fi
    max_size=$((20 * 1024 * 1024))
    if [ "$file_size" -gt "$max_size" ]; then
      size_mb=$(( file_size / 1024 / 1024 ))
      log "error: video file exceeds 20MB limit (${size_mb}MB): $video_source"
      echo "Error: Video file exceeds Gemini CLI's 20MB limit (${size_mb}MB). Compress or trim the video first."
      exit 1
    fi

    # Copy video to a temp staging dir so --include-directories doesn't expose the parent.
    # Max 20MB (enforced above), cleaned up on exit.
    video_stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/midflight-video.XXXXXX")
    cp "$video_source" "$video_stage_dir/video_input.mp4"
    video_source="$video_stage_dir/video_input.mp4"
  fi
else
  # --- Text modes: arg1 is a query file ---
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
  val=$(grep '^provider=' "$config_file" | cut -d= -f2- | tr -d '[:space:]' || true)
  [ -n "$val" ] && provider="$val"

  val=$(grep '^codex_model=' "$config_file" | cut -d= -f2- | tr -d '[:space:]' || true)
  [ -n "$val" ] && codex_model="$val"
  val=$(grep '^codex_reasoning_effort=' "$config_file" | cut -d= -f2- | tr -d '[:space:]' || true)
  [ -n "$val" ] && codex_reasoning_effort="$val"
  val=$(grep '^gemini_model=' "$config_file" | cut -d= -f2- | tr -d '[:space:]' || true)
  [ -n "$val" ] && gemini_model="$val"

  log "config loaded: provider=$provider"
else
  log "no config file found at $config_file, using defaults"
fi

# Video mode requires Gemini (multimodal)
if [ "$mode" = "video" ]; then
  if [ "$provider" != "gemini" ]; then
    log "video mode: overriding provider=$provider → gemini (video requires multimodal)"
  fi
  provider="gemini"
fi

# ---------------------------------------------------------------------------
# Preflight dependency check
# ---------------------------------------------------------------------------
if ! command -v "$provider" >/dev/null 2>&1; then
  case "$provider" in
    codex)  install_url="https://github.com/openai/codex" ;;
    gemini) install_url="https://github.com/google-gemini/gemini-cli" ;;
    *)      install_url="" ;;
  esac
  log "error: '$provider' not found in PATH"
  echo "Error: '$provider' CLI not found. Install it: $install_url"
  exit 1
fi

# ---------------------------------------------------------------------------
# System prompt — selected by mode
# ---------------------------------------------------------------------------
CONSULT_PROMPT='You are a senior engineer being consulted mid-development. Another engineer (an AI assistant) is working on a task and needs your perspective.

Be direct and concise:
- If you see a clear issue, say so immediately
- If the approach looks sound, confirm briefly and suggest next steps
- If there are multiple valid paths, lay out the tradeoffs in bullets
- Don'"'"'t rehash what they already know — add new signal only
- Do NOT modify any files. Provide advice only.'

IMPLEMENT_PROMPT='You are an implementation engineer. Another engineer (an AI assistant) has specified exact changes that need to be made.

Your job:
- Read the existing files referenced in the task
- Apply the described edits precisely
- Run any verification commands specified (typecheck, lint, tests)
- Report what you changed and the verification results
- If something is ambiguous, make the conservative choice and note it'

VIDEO_PROMPT='You are a video analyst reviewing footage for a creative team. You have deep expertise in video production, advertising, and visual storytelling.

Your job:
- Analyze the video thoroughly and respond to the prompt
- For scene breakdowns: describe visuals, text overlays, transitions, mood, pacing, and estimated duration per scene
- Note any quality issues: audio sync, resolution, jarring cuts, placeholder content
- If the video is an ad: evaluate messaging clarity, call-to-action effectiveness, brand consistency
- Be specific and actionable — the team will use your analysis to iterate
- Do NOT modify any files. Provide analysis only.'

case "$mode" in
  implement) SYSTEM_PROMPT="$IMPLEMENT_PROMPT" ;;
  video)     SYSTEM_PROMPT="$VIDEO_PROMPT" ;;
  *)         SYSTEM_PROMPT="$CONSULT_PROMPT" ;;
esac

log "mode=$mode"

# Claude plugin invocations can leave stdin connected to an open pipe.
# Codex treats piped stdin as extra prompt content even when a prompt argument
# is provided, which can block until the parent closes stdin. This script never
# reads from stdin, so detach here before invoking any provider CLI.
exec </dev/null

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
    --skip-git-repo-check \
    -o "$output_file" \
    "$full_prompt" \
    2>&1 | while IFS= read -r line; do log "codex: $line"; done
}

query_gemini() {
  local full_prompt="$1"
  local output_file="$2"
  local include_dir="${3:-}"

  # Always sandbox; add --include-directories when accessing files outside cwd
  local sandbox_args=(--sandbox)
  if [ -n "$include_dir" ]; then
    sandbox_args+=(--include-directories "$include_dir")
  fi

  gemini \
    -p "$full_prompt" \
    -m "$gemini_model" \
    "${sandbox_args[@]}" \
    --output-format text \
    > "$output_file" \
    2> >(while IFS= read -r line; do log "gemini: $line"; done)
}

# ---------------------------------------------------------------------------
# Build the full prompt (system prompt + query/video content)
# ---------------------------------------------------------------------------
if [ "$mode" = "video" ]; then
  # URLs go directly in the prompt; local files use @path for Gemini CLI
  if [ "$video_is_url" = true ]; then
    video_ref="$video_source"
  else
    video_ref="@${video_source}"
  fi

  full_prompt="${SYSTEM_PROMPT}

---

${video_prompt}

${video_ref}"
  log "sending video query to gemini (source: ${video_source##*/}, prompt: ${#video_prompt} chars)..."
else
  full_prompt="${SYSTEM_PROMPT}

---

${query_content}"
  log "sending query to $provider (${#query_content} chars)..."
fi

response_file=$(mktemp "${TMPDIR:-/tmp}/midflight-response.XXXXXX")
trap 'rm -f "$response_file"; [ -n "${video_stage_dir:-}" ] && rm -rf "$video_stage_dir"' EXIT
start_time=$SECONDS

case "$provider" in
  codex)
    if ! query_codex "$full_prompt" "$response_file"; then
      log "codex exec failed"
      echo "Error: Codex query failed. Make sure the Codex CLI is installed and authenticated."
      exit 1
    fi
    ;;
  gemini)
    gemini_include_dir=""
    if [ "$mode" = "video" ] && [ "$video_is_url" = false ]; then
      gemini_include_dir="$(dirname "$video_source")"
    fi
    if ! query_gemini "$full_prompt" "$response_file" "$gemini_include_dir"; then
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

duration=$(( SECONDS - start_time ))
log "response received (${#response} chars) in ${duration}s"
echo "$response"
