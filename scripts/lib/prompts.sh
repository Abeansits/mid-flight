PROMPT_CONTENT=""

read_prompt_file() {
  local prompt_name="$1"
  local prompt_path="$PROMPTS_DIR/$prompt_name"

  if [ ! -f "$prompt_path" ]; then
    error_exit "missing prompt file: $prompt_path" "Error: Missing prompt file: $prompt_path"
  fi

  PROMPT_CONTENT="$(cat "$prompt_path")"
}

load_system_prompt() {
  local mode="$1"

  case "$mode" in
    implement) read_prompt_file "implement.md" ;;
    video) read_prompt_file "video.md" ;;
    *) read_prompt_file "consult.md" ;;
  esac
}

load_default_video_prompt() {
  read_prompt_file "video-default.md"
}
