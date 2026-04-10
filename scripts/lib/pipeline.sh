MODE=""
INPUT_PATH=""
VIDEO_PROMPT_OVERRIDE=""
QUERY_CONTENT=""
VIDEO_SOURCE=""
VIDEO_PROMPT=""
VIDEO_IS_URL="false"
FULL_PROMPT=""
GEMINI_INCLUDE_DIR=""
RESPONSE_FILE=""
RESPONSE_CONTENT=""

parse_args() {
  if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
    error_exit "missing query file path" "Error: No query file provided. Usage: query.sh <query-file-path>"
  fi

  INPUT_PATH="$1"
  MODE="${2:-consult}"

  case "$MODE" in
    consult|implement|video) ;;
    *)
      log "unknown mode '$MODE', defaulting to consult"
      MODE="consult"
      ;;
  esac

  if [ "$MODE" = "video" ]; then
    VIDEO_PROMPT_OVERRIDE="${3:-}"
  fi
}

load_request_payload() {
  case "$MODE" in
    video) prepare_video_request ;;
    *) prepare_text_request ;;
  esac
}

prepare_text_request() {
  local query_copy

  if [ ! -f "$INPUT_PATH" ]; then
    error_exit "query file not found: $INPUT_PATH" "Error: Query file not found: $INPUT_PATH"
  fi

  query_copy="$RUN_DIR/query.md"
  cp "$INPUT_PATH" "$query_copy"
  QUERY_CONTENT="$(cat "$query_copy")"

  if [ -z "$QUERY_CONTENT" ]; then
    error_exit "query file is empty: $INPUT_PATH" "Error: Query file is empty."
  fi
}

prepare_video_request() {
  local staged_video

  VIDEO_SOURCE="$INPUT_PATH"

  if [ -n "$VIDEO_PROMPT_OVERRIDE" ]; then
    VIDEO_PROMPT="$VIDEO_PROMPT_OVERRIDE"
  else
    load_default_video_prompt
    VIDEO_PROMPT="$PROMPT_CONTENT"
  fi

  if [[ "$VIDEO_SOURCE" =~ ^https?:// ]]; then
    VIDEO_IS_URL="true"
    log "video source: URL"
    return
  fi

  if [ ! -f "$VIDEO_SOURCE" ]; then
    error_exit "video file not found: $VIDEO_SOURCE" "Error: Video file not found: $VIDEO_SOURCE"
  fi

  validate_video_file "$VIDEO_SOURCE"

  staged_video="$RUN_DIR/video_input.mp4"
  cp "$VIDEO_SOURCE" "$staged_video"
  VIDEO_SOURCE="$staged_video"
  GEMINI_INCLUDE_DIR="$(dirname "$VIDEO_SOURCE")"
}

validate_video_file() {
  local video_path="$1"
  local file_size
  local max_size=$((20 * 1024 * 1024))
  local size_mb

  file_size="$(stat -f%z "$video_path" 2>/dev/null || stat -c%s "$video_path" 2>/dev/null || echo "")"

  if [ -z "$file_size" ] || [ "$file_size" -eq 0 ]; then
    error_exit \
      "could not determine file size: $video_path" \
      "Error: Could not determine file size for: $video_path"
  fi

  if [ "$file_size" -gt "$max_size" ]; then
    size_mb=$((file_size / 1024 / 1024))
    error_exit \
      "video file exceeds 20MB limit (${size_mb}MB): $video_path" \
      "Error: Video file exceeds Gemini CLI's 20MB limit (${size_mb}MB). Compress or trim the video first."
  fi
}

build_full_prompt() {
  local video_ref

  load_system_prompt "$MODE"

  if [ "$MODE" = "video" ]; then
    if [ "$VIDEO_IS_URL" = "true" ]; then
      video_ref="$VIDEO_SOURCE"
    else
      video_ref="@${VIDEO_SOURCE}"
    fi

    FULL_PROMPT="${PROMPT_CONTENT}

---

${VIDEO_PROMPT}

${video_ref}"
    printf '%s' "$FULL_PROMPT" > "$RUN_DIR/full_prompt.txt"
    log "sending video query to gemini (source: ${VIDEO_SOURCE##*/}, prompt: ${#VIDEO_PROMPT} chars)..."
    return
  fi

  FULL_PROMPT="${PROMPT_CONTENT}

---

${QUERY_CONTENT}"
  printf '%s' "$FULL_PROMPT" > "$RUN_DIR/full_prompt.txt"
  log "sending query to $provider (${#QUERY_CONTENT} chars)..."
}

read_response() {
  local response_file="$1"
  local provider_name="$2"

  RESPONSE_CONTENT="$(cat "$response_file" 2>/dev/null || echo "")"

  if [ -z "$RESPONSE_CONTENT" ]; then
    error_exit \
      "$provider_name returned empty response" \
      "Error: $provider_name returned an empty response. Try again or switch providers in ~/.config/mid-flight/config"
  fi
}
