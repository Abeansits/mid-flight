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
    agy|antigravity) printf '%s\n' "Antigravity" ;;
    opencode) printf '%s\n' "OpenCode" ;;
    oz) printf '%s\n' "Oz" ;;
    grok|grok-build) printf '%s\n' "Grok" ;;
    claude) printf '%s\n' "Claude" ;;
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
  local sandbox_mode="read-only"

  prepare_provider_run \
    "codex" \
    "codex.log" \
    "Error: Codex query failed. Make sure the Codex CLI is installed and authenticated."

  # `--sandbox` only gates model-generated shell/tool writes (codex-cli help),
  # not host session/rollout files under $CODEX_HOME. Consult/video stay
  # read-only; only implement needs workspace-write to apply edits.
  if [ "${MODE:-}" = "implement" ]; then
    sandbox_mode="workspace-write"
  fi

  codex exec \
    --model "$codex_model" \
    -c "model_reasoning_effort=\"$codex_reasoning_effort\"" \
    --sandbox "$sandbox_mode" \
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
  local include_args=()

  if [ -n "$include_dir" ]; then
    include_args+=(--include-directories "$include_dir")
  fi

  prepare_provider_run \
    "gemini" \
    "gemini.log" \
    "Error: Gemini query failed. Make sure the Gemini CLI is installed and authenticated."

  gemini \
    -p "$full_prompt" \
    -m "$gemini_model" \
    ${include_args[@]+"${include_args[@]}"} \
    --output-format text \
    > "$output_file" \
    2> "$PROVIDER_LOG_FILE"
}

query_agy() {
  local full_prompt="$1"
  local output_file="$2"
  local include_dir="${3:-}"
  local args=(-p "$full_prompt" --output-format text)

  prepare_provider_run \
    "agy" \
    "agy.log" \
    "Error: Antigravity query failed. Make sure the Antigravity CLI (agy) is installed and authenticated."

  if [ -n "$agy_model" ]; then
    args+=(--model "$agy_model")
  fi

  if [ -n "$agy_effort" ]; then
    args+=(--effort "$agy_effort")
  fi

  if [ -n "$include_dir" ]; then
    args+=(--add-dir "$include_dir")
  fi

  # Headless agy soft-denies writes unless permissions are skipped.
  # Consult/video stay gated; implement is the only mode that must edit files.
  if [ "${MODE:-}" = "implement" ]; then
    args+=(--dangerously-skip-permissions)
  fi

  agy "${args[@]}" \
    > "$output_file" \
    2> "$PROVIDER_LOG_FILE"
}

query_opencode() {
  local full_prompt="$1"
  local output_file="$2"
  local args=(run)
  local version=""
  local model="$opencode_model"

  prepare_provider_run \
    "opencode" \
    "opencode.log" \
    "Error: OpenCode query failed. Make sure the opencode CLI is installed and authenticated."

  version="$(opencode --version 2>/dev/null)" || version=""
  if [[ "$version" =~ ^(opencode[[:space:]]+)?v?([0-9]+)\. ]] && [ "${BASH_REMATCH[2]}" -ge 2 ]; then
    # OpenCode v2 uses the inherited cwd and encodes the variant in the model.
    # Preserve an explicit model suffix over the default configured variant.
    if [ -n "$model" ] && [ -n "$opencode_variant" ] && [[ "$model" != *'#'* ]]; then
      model="${model}#${opencode_variant}"
    elif [ -z "$model" ] && [ -n "$opencode_variant" ]; then
      log "opencode: v2 has no standalone variant flag; opencode_variant=$opencode_variant is ignored without opencode_model"
    fi
  else
    # Preserve v1 behavior if an older CLI cannot report its version.
    args+=(--dir "$PWD")
    if [ -n "$opencode_variant" ]; then
      args+=(--variant "$opencode_variant")
    fi
  fi

  if [ -n "$model" ]; then
    args+=(--model "$model")
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


query_grok() {
  local full_prompt="$1"
  local output_file="$2"
  local args=(-p "$full_prompt" --output-format plain)

  prepare_provider_run \
    "grok" \
    "grok.log" \
    "Error: Grok query failed. Make sure the Grok CLI is installed and authenticated."

  if [ -n "$grok_model" ]; then
    args+=(-m "$grok_model")
  fi

  if [ -n "$grok_effort" ]; then
    args+=(--effort "$grok_effort")
  fi

  # Consult/video stay gated; implement must auto-approve tool calls.
  if [ "${MODE:-}" = "implement" ]; then
    args+=(--always-approve)
  fi

  grok "${args[@]}" \
    > "$output_file" \
    2> "$PROVIDER_LOG_FILE"
}

query_claude() {
  local full_prompt="$1"
  local output_file="$2"
  local args=(-p "$full_prompt" --output-format text)

  prepare_provider_run \
    "claude" \
    "claude.log" \
    "Error: Claude query failed. Make sure the Claude Code CLI is installed and authenticated."

  if [ -n "$claude_model" ]; then
    args+=(--model "$claude_model")
  fi

  # Consult/video stay gated; implement must skip permission prompts to edit.
  if [ "${MODE:-}" = "implement" ]; then
    args+=(--dangerously-skip-permissions)
  fi

  claude "${args[@]}" \
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
    agy)
      query_agy "$full_prompt" "$output_file" "$include_dir"
      ;;
    opencode)
      query_opencode "$full_prompt" "$output_file"
      ;;
    oz)
      query_oz "$full_prompt" "$output_file"
      ;;
    grok)
      query_grok "$full_prompt" "$output_file"
      ;;
    claude)
      query_claude "$full_prompt" "$output_file"
      ;;
    *)
      error_exit \
        "unknown provider: $provider_name" \
        "Error: Unknown provider '$provider_name'. Supported: codex, gemini, agy, opencode, oz, grok, claude. Check ~/.config/mid-flight/config"
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
