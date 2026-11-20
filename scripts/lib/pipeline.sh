# shellcheck shell=bash disable=SC2034,SC2154

MODE=""
INPUT_PATH=""
VIDEO_PROMPT_OVERRIDE=""
QUERY_CONTENT=""
VIDEO_SOURCE=""
VIDEO_PROMPT=""
# Below this video bitrate a shrunk file is not worth analyzing.
VIDEO_MIN_KBPS=60
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
    consult|implement|video|image-gen|video-gen) ;;
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
  local stage_dir="$RUN_DIR/video"
  local staged_video
  local source_ext
  local file_size
  local max_bytes
  local needs_convert="false"

  VIDEO_SOURCE="$INPUT_PATH"

  # The provider is given this directory. It holds the video and nothing
  # else, so prompts, logs, and downloads stay out of its view.
  mkdir -p "$stage_dir"

  if [ -n "$VIDEO_PROMPT_OVERRIDE" ]; then
    VIDEO_PROMPT="$VIDEO_PROMPT_OVERRIDE"
  else
    load_default_video_prompt
    VIDEO_PROMPT="$PROMPT_CONTENT"
  fi

  if [[ "$VIDEO_SOURCE" =~ ^https?:// ]]; then
    # Neither CLI watches a remote video. agy has no URL tool in print mode and
    # Gemini's web_fetch reads the page, not the footage. Download it and
    # carry on as a local file.
    download_video_url "$VIDEO_SOURCE"
  fi

  if [ ! -f "$VIDEO_SOURCE" ]; then
    error_exit "video file not found: $VIDEO_SOURCE" "Error: Video file not found: $VIDEO_SOURCE"
  fi

  file_size="$(video_file_size "$VIDEO_SOURCE")"
  if [ -z "$file_size" ] || [ "$file_size" -eq 0 ]; then
    error_exit \
      "could not determine file size: $VIDEO_SOURCE" \
      "Error: Could not determine file size for: $VIDEO_SOURCE"
  fi

  max_bytes="$(video_max_bytes "$provider")"
  source_ext="$(video_extension "$VIDEO_SOURCE")"

  if ! video_extension_is_native "$provider" "$source_ext"; then
    needs_convert="true"
  fi

  if [ "$file_size" -gt "$max_bytes" ] || [ "$needs_convert" = "true" ]; then
    if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
      staged_video="$stage_dir/video_input.mp4"
      if [ "$file_size" -gt "$max_bytes" ]; then
        log "video is $(bytes_to_mb "$file_size")MB, over the $(bytes_to_mb "$max_bytes")MB $(provider_display_name "$provider") limit; shrinking with ffmpeg (long videos take a while)..."
      else
        log "video format .$source_ext is not read by $(provider_display_name "$provider"); converting to MP4 with ffmpeg..."
      fi
      transcode_video_to_fit "$VIDEO_SOURCE" "$staged_video" "$max_bytes"
      VIDEO_SOURCE="$staged_video"
      GEMINI_INCLUDE_DIR="$stage_dir"
      return
    fi

    if [ "$file_size" -gt "$max_bytes" ]; then
      error_exit \
        "video file exceeds $(bytes_to_mb "$max_bytes")MB limit ($(bytes_to_mb "$file_size")MB): $VIDEO_SOURCE" \
        "Error: Video file is $(bytes_to_mb "$file_size")MB and $(provider_display_name "$provider") reads at most $(bytes_to_mb "$max_bytes")MB. Install ffmpeg and MidFlight shrinks it for you, or compress or trim the video first."
    fi

    log "video format .$source_ext may not be read by $(provider_display_name "$provider"); install ffmpeg to convert it automatically"
  fi

  # Keep the real extension. The provider picks a decoder from it.
  staged_video="$stage_dir/video_input.${source_ext}"
  case "$VIDEO_SOURCE" in
    "$RUN_DIR"/*) mv "$VIDEO_SOURCE" "$staged_video" ;;  # our own download
    *) cp "$VIDEO_SOURCE" "$staged_video" ;;
  esac
  VIDEO_SOURCE="$staged_video"
  GEMINI_INCLUDE_DIR="$stage_dir"
}

video_file_size() {
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo ""
}

# Rounds up, so a file just over a limit never prints as equal to it.
bytes_to_mb() {
  printf '%s\n' "$(( ($1 + 1048575) / 1048576 ))"
}

# Lowercased extension without the dot. Defaults to mp4.
video_extension() {
  local name="${1##*/}"
  local ext=""

  case "$name" in
    *.*) ext="$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')" ;;
  esac

  case "$ext" in
    ""|*[!a-z0-9]*) ext="mp4" ;;
  esac

  printf '%s\n' "$ext"
}

# Largest file each CLI's file tool accepts, measured against agy 1.5.7
# ("exceeds the 100 MB limit") and Gemini CLI 0.43 ("exceeds the 20MB limit").
# MIDFLIGHT_VIDEO_MAX_MB overrides both.
video_max_bytes() {
  local provider_name="$1"
  local max_mb=""

  if [[ "${MIDFLIGHT_VIDEO_MAX_MB:-}" =~ ^[1-9][0-9]*$ ]]; then
    max_mb="$MIDFLIGHT_VIDEO_MAX_MB"
  elif [ -n "${MIDFLIGHT_VIDEO_MAX_MB:-}" ]; then
    log "ignoring MIDFLIGHT_VIDEO_MAX_MB='$MIDFLIGHT_VIDEO_MAX_MB' (positive integer expected)"
  fi

  if [ -z "$max_mb" ]; then
    case "$provider_name" in
      gemini) max_mb=20 ;;
      *) max_mb=100 ;;
    esac
  fi

  printf '%s\n' "$(( max_mb * 1024 * 1024 ))"
}

video_extension_is_native() {
  local provider_name="$1"
  local ext="$2"

  case "$ext" in
    mp4|m4v|mov|webm|avi) return 0 ;;
  esac

  # agy 1.5.7 was checked with MP4, MOV, WebM, AVI, and MKV. The Gemini list
  # follows the Gemini API's documented video types.
  case "$provider_name" in
    gemini)
      case "$ext" in
        mpeg|mpg|flv|wmv|3gp|3gpp) return 0 ;;
      esac
      ;;
    *)
      case "$ext" in
        mkv) return 0 ;;
      esac
      ;;
  esac

  return 1
}

# Fetch a remote video into the run workspace and point VIDEO_SOURCE at it.
# yt-dlp handles YouTube and most hosts. Without it, only a direct link to a
# media file can be fetched, with curl.
download_video_url() {
  local url="$1"
  local download_dir="$RUN_DIR/download"
  local download_log="$RUN_DIR/download.log"
  local max_height="${MIDFLIGHT_VIDEO_MAX_HEIGHT:-720}"
  local url_file=""
  local url_ext=""
  local candidate=""
  local downloaded=""
  local args=()

  mkdir -p "$download_dir"

  if ! [[ "$max_height" =~ ^[1-9][0-9]*$ ]]; then
    log "ignoring MIDFLIGHT_VIDEO_MAX_HEIGHT='$max_height' (positive integer expected)"
    max_height=720
  fi

  if command -v yt-dlp >/dev/null 2>&1; then
    log "video source: URL, downloading with yt-dlp (up to ${max_height}p)..."
    args=(--no-playlist --no-progress --quiet --no-warnings --socket-timeout 30
      --match-filter '!is_live' -o "$download_dir/video.%(ext)s")
    if command -v ffmpeg >/dev/null 2>&1; then
      args+=(-f 'bv*+ba/b' -S "res:${max_height},ext:mp4:m4a" --merge-output-format mp4)
    else
      # Separate video and audio streams need ffmpeg to merge. Take one
      # pre-merged file instead.
      args+=(-f 'b' -S "res:${max_height},ext:mp4")
    fi

    if ! yt-dlp "${args[@]}" -- "$url" > "$download_log" 2>&1; then
      error_exit \
        "yt-dlp failed for $url" \
        "Error: Could not download the video with yt-dlp.$(provider_error_excerpt "$download_log") Try 'yt-dlp -U', or download the file yourself and pass the path."
    fi
  else
    # Only a link whose last path segment names a media file is fetched
    # directly. A watch page would download as HTML.
    url_file="${url%%[?#]*}"
    url_file="${url_file##*/}"
    case "$url_file" in
      *.*) url_ext="$(video_extension "$url_file")" ;;
    esac
    case "$url_ext" in
      mp4|m4v|mov|webm|avi|mkv|mpeg|mpg|flv|wmv|3gp) ;;
      *)
        error_exit \
          "yt-dlp not found; cannot download $url" \
          "Error: Video links need yt-dlp. The provider cannot watch a URL, so MidFlight downloads it first. Install it: $YT_DLP_INSTALL_URL (macOS: brew install yt-dlp). Or download the video and pass the file path."
        ;;
    esac

    if ! command -v curl >/dev/null 2>&1; then
      error_exit \
        "neither yt-dlp nor curl found; cannot download $url" \
        "Error: Video links need yt-dlp or curl to download. Install yt-dlp: $YT_DLP_INSTALL_URL"
    fi

    log "video source: URL, downloading with curl..."
    if ! curl -fsSL --connect-timeout 30 -o "$download_dir/video.${url_ext}" -- "$url" > "$download_log" 2>&1; then
      error_exit \
        "curl failed for $url" \
        "Error: Could not download the video.$(provider_error_excerpt "$download_log") Download the file yourself and pass the path."
    fi
  fi

  for candidate in "$download_dir"/video.*; do
    case "$candidate" in
      *.part|*.ytdl|*.tmp) continue ;;
    esac
    if [ -f "$candidate" ]; then
      downloaded="$candidate"
      break
    fi
  done

  if [ -z "$downloaded" ] || [ ! -s "$downloaded" ]; then
    error_exit \
      "download produced no file for $url" \
      "Error: The video download produced no file.$(provider_error_excerpt "$download_log") A live stream cannot be analyzed. Download the file yourself and pass the path."
  fi

  log "downloaded $(bytes_to_mb "$(video_file_size "$downloaded")")MB (${downloaded##*/})"
  VIDEO_SOURCE="$downloaded"
}

# Re-encode to H.264/AAC MP4 at a bitrate that fits max_bytes. The providers
# sample about one frame per second, so resolution and a readable picture
# matter more than frame rate.
transcode_video_to_fit() {
  local source_path="$1"
  local dest_path="$2"
  local max_bytes="$3"
  local transcode_log="$RUN_DIR/ffmpeg.log"
  local duration=""
  local audio_kbps=48
  local total_kbps
  local video_kbps
  local height
  local fps
  local attempt
  local out_size=""

  duration="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$source_path" 2>/dev/null | head -n 1)"
  duration="${duration%%.*}"
  if ! [[ "$duration" =~ ^[0-9]+$ ]]; then
    error_exit \
      "ffprobe could not read the duration: $source_path" \
      "Error: ffprobe could not read this video, so MidFlight cannot convert it. Check that the file is a playable video."
  fi
  duration=$((duration + 1))

  # 8% headroom for the container and bitrate overshoot.
  total_kbps=$(( max_bytes * 8 * 92 / 100 / 1000 / duration ))
  video_kbps=$(( total_kbps - audio_kbps ))

  for attempt in 1 2; do
    if [ "$video_kbps" -lt "$VIDEO_MIN_KBPS" ]; then
      error_exit \
        "video too long to fit $(bytes_to_mb "$max_bytes")MB (${duration}s leaves ${video_kbps}kbps)" \
        "Error: This video is too long to fit $(provider_display_name "$provider")'s $(bytes_to_mb "$max_bytes")MB limit at a watchable quality ($((duration / 60)) min). Trim it, or split it into parts."
    fi
    [ "$video_kbps" -gt 2500 ] && video_kbps=2500

    # A tight budget goes to picture detail first, then frame rate.
    if [ "$video_kbps" -ge 1200 ]; then
      height=720
      fps=12
    elif [ "$video_kbps" -ge 350 ]; then
      height=480
      fps=12
    else
      height=360
      fps=6
    fi

    log "ffmpeg: ${height}p at ${fps}fps, ${video_kbps}kbps video, ${audio_kbps}kbps audio"
    if ! ffmpeg -nostdin -hide_banner -loglevel error -y \
      -i "$source_path" \
      -map 0:v:0 -map '0:a:0?' \
      -vf "scale=-2:'min(${height},ih)',fps=${fps}" \
      -c:v libx264 -preset veryfast \
      -b:v "${video_kbps}k" -maxrate "${video_kbps}k" -bufsize "$((video_kbps * 2))k" \
      -pix_fmt yuv420p \
      -c:a aac -b:a "${audio_kbps}k" -ac 1 \
      -movflags +faststart \
      "$dest_path" > "$transcode_log" 2>&1; then
      error_exit \
        "ffmpeg failed on $source_path" \
        "Error: ffmpeg could not convert the video.$(provider_error_excerpt "$transcode_log")"
    fi

    out_size="$(video_file_size "$dest_path")"
    if [ -n "$out_size" ] && [ "$out_size" -gt 0 ] && [ "$out_size" -le "$max_bytes" ]; then
      log "video ready: $(bytes_to_mb "$out_size")MB"
      return
    fi

    # Overshot the budget. Try once more at 70%.
    video_kbps=$(( video_kbps * 70 / 100 ))
  done

  error_exit \
    "ffmpeg output still exceeds $(bytes_to_mb "$max_bytes")MB" \
    "Error: Could not shrink the video under $(provider_display_name "$provider")'s $(bytes_to_mb "$max_bytes")MB limit. Trim it, or split it into parts."
}

build_full_prompt() {
  local video_ref

  load_system_prompt "$MODE"

  if [ "$MODE" = "video" ]; then
    if [ "$provider" = "gemini" ]; then
      video_ref="@${VIDEO_SOURCE}"
    else
      # Antigravity has no Gemini-style @path inline syntax; --add-dir
      # exposes the staged file and the prompt names it by path. Without the
      # second line agy tends to probe the file with ffprobe and scripts, or
      # wander through the workspace, which is slower and cannot hear the
      # audio.
      video_ref="Video file: ${VIDEO_SOURCE}
Open that file with your file-reading tool to watch and listen to it directly. Base the analysis on the video. Do not explore the workspace, and do not use ffmpeg, ffprobe, or scripts unless the file-reading tool fails."
    fi

    FULL_PROMPT="${PROMPT_CONTENT}

---

${VIDEO_PROMPT}

${video_ref}"
    printf '%s' "$FULL_PROMPT" > "$RUN_DIR/full_prompt.txt"
    log "sending video query to $provider (source: ${VIDEO_SOURCE##*/}, prompt: ${#VIDEO_PROMPT} chars)..."
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
