# shellcheck shell=bash disable=SC2154

detach_provider_stdin() {
  # Claude plugin invocations can leave stdin connected to an open pipe.
  # Codex treats piped stdin as extra prompt content even when a prompt argument
  # is provided, which can block until the parent closes stdin. This script
  # never reads from stdin, so detach before invoking provider CLIs.
  exec </dev/null
}

PROVIDER_LOG_FILE=""
PROVIDER_FAILURE_DETAIL=""
PROVIDER_FAILURE_MESSAGE=""

provider_display_name() {
  case "$1" in
    codex) printf '%s\n' "Codex" ;;
    gemini) printf '%s\n' "Gemini" ;;
    opencode) printf '%s\n' "OpenCode" ;;
    oz) printf '%s\n' "Oz" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

provider_error_excerpt() {
  local log_file="$1"
  local excerpt=""

  if [ ! -f "$log_file" ]; then
    return 0
  fi

  excerpt="$(tail -n 3 "$log_file" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"

  if [ -n "$excerpt" ]; then
    printf ' Details: %s\n' "$excerpt"
  fi
}

emit_provider_logs() {
  local provider_name="$1"
  local log_file="$2"

  if [ ! -f "$log_file" ]; then
    return
  fi

  while IFS= read -r line; do
    log "$provider_name: $line"
  done < "$log_file"
}

prepare_provider_run() {
  local provider_name="$1"
  local log_filename="$2"
  local failure_message="$3"

  PROVIDER_LOG_FILE="$RUN_DIR/$log_filename"
  PROVIDER_FAILURE_DETAIL="${provider_name} exec failed"
  PROVIDER_FAILURE_MESSAGE="$failure_message"
}

classify_provider_failure() {
  local provider_name="$1"
  local log_file="$2"
  local provider_label
  local excerpt=""
  local log_text=""
  local normalized=""

  provider_label="$(provider_display_name "$provider_name")"
  excerpt="$(provider_error_excerpt "$log_file")"

  if [ -f "$log_file" ]; then
    log_text="$(cat "$log_file")"
  fi

  normalized="$(printf '%s' "$log_text" | tr '[:upper:]' '[:lower:]')"

  case "$normalized" in
    *unauthorized*|*"authentication failed"*|*"invalid api key"*|*"not logged in"*|*"login required"*|*forbidden*|*"permission denied"*|*invalid_auth*)
      PROVIDER_FAILURE_DETAIL="${provider_name} authentication failed"
      PROVIDER_FAILURE_MESSAGE="Error: ${provider_label} authentication failed. Re-authenticate the ${provider_label} CLI and try again.${excerpt}"
      ;;
    *"rate limit"*|*rate_limit*|*"too many requests"*|*"quota exceeded"*|*"resource exhausted"*|*"status 429"*|*"error 429"*)
      PROVIDER_FAILURE_DETAIL="${provider_name} rate limited"
      PROVIDER_FAILURE_MESSAGE="Error: ${provider_label} hit a rate limit or quota. Wait a bit, then try again.${excerpt}"
      ;;
    *"timed out"*|*timeout*|*"network error"*|*"connection reset"*|*"connection refused"*|*"could not resolve"*|*"temporary failure in name resolution"*|*enotfound*|*econnreset*|*dns*)
      PROVIDER_FAILURE_DETAIL="${provider_name} network error"
      PROVIDER_FAILURE_MESSAGE="Error: ${provider_label} failed because of a network issue. Check connectivity and try again.${excerpt}"
      ;;
  esac
}

query_codex() {
  local full_prompt="$1"
  local output_file="$2"

  prepare_provider_run \
    "codex" \
    "codex.log" \
    "Error: Codex query failed. Make sure the Codex CLI is installed and authenticated."

  codex exec \
    --model "$codex_model" \
    -c "model_reasoning_effort=\"$codex_reasoning_effort\"" \
    --full-auto \
    --skip-git-repo-check \
    -o "$output_file" \
    "$full_prompt" \
    > "$PROVIDER_LOG_FILE" \
    2>&1
}

query_gemini() {
  local full_prompt="$1"
  local output_file="$2"
  local include_dir="${3:-}"
  local sandbox_args=(--sandbox)

  if [ -n "$include_dir" ]; then
    sandbox_args+=(--include-directories "$include_dir")
  fi

  prepare_provider_run \
    "gemini" \
    "gemini.log" \
    "Error: Gemini query failed. Make sure the Gemini CLI is installed and authenticated."

  gemini \
    -p "$full_prompt" \
    -m "$gemini_model" \
    "${sandbox_args[@]}" \
    --output-format text \
    > "$output_file" \
    2> "$PROVIDER_LOG_FILE"
}

query_opencode() {
  local full_prompt="$1"
  local output_file="$2"
  local args=(run --dir "$PWD")

  prepare_provider_run \
    "opencode" \
    "opencode.log" \
    "Error: OpenCode query failed. Make sure the opencode CLI is installed and authenticated."

  if [ -n "$opencode_model" ]; then
    args+=(--model "$opencode_model")
  fi

  if [ -n "$opencode_variant" ]; then
    args+=(--variant "$opencode_variant")
  fi

  if [ -n "$opencode_format" ]; then
    args+=(--format "$opencode_format")
  fi

  args+=("$full_prompt")

  opencode "${args[@]}" \
    > "$output_file" \
    2> "$PROVIDER_LOG_FILE"
}

query_oz() {
  local full_prompt="$1"
  local output_file="$2"
  local args=(agent run --prompt "$full_prompt" --output-format "$oz_output_format" -C "$PWD")

  prepare_provider_run \
    "oz" \
    "oz.log" \
    "Error: Oz query failed. Make sure the oz CLI is installed and authenticated."

  if [ -n "$oz_model" ]; then
    args+=(--model "$oz_model")
  fi

  if [ -n "$oz_profile" ]; then
    args+=(--profile "$oz_profile")
  fi

  oz "${args[@]}" \
    > "$output_file" \
    2> "$PROVIDER_LOG_FILE"
}

run_provider_command() {
  local provider_name="$1"
  local full_prompt="$2"
  local output_file="$3"
  local include_dir="${4:-}"

  case "$provider_name" in
    codex)
      query_codex "$full_prompt" "$output_file"
      ;;
    gemini)
      query_gemini "$full_prompt" "$output_file" "$include_dir"
      ;;
    opencode)
      query_opencode "$full_prompt" "$output_file"
      ;;
    oz)
      query_oz "$full_prompt" "$output_file"
      ;;
    *)
      error_exit \
        "unknown provider: $provider_name" \
        "Error: Unknown provider '$provider_name'. Supported: codex, gemini, opencode, oz. Check ~/.config/mid-flight/config"
      ;;
  esac
}

run_provider_query() {
  local provider_name="$1"
  local full_prompt="$2"
  local output_file="$3"
  local include_dir="${4:-}"
  local status=0

  PROVIDER_LOG_FILE=""
  PROVIDER_FAILURE_DETAIL=""
  PROVIDER_FAILURE_MESSAGE=""

  set +e
  run_provider_command "$provider_name" "$full_prompt" "$output_file" "$include_dir"
  status=$?
  set -e

  emit_provider_logs "$provider_name" "$PROVIDER_LOG_FILE"

  if [ "$status" -ne 0 ]; then
    classify_provider_failure "$provider_name" "$PROVIDER_LOG_FILE"
    error_exit "$PROVIDER_FAILURE_DETAIL" "$PROVIDER_FAILURE_MESSAGE"
  fi
}
