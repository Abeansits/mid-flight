detach_provider_stdin() {
  # Claude plugin invocations can leave stdin connected to an open pipe.
  # Codex treats piped stdin as extra prompt content even when a prompt argument
  # is provided, which can block until the parent closes stdin. This script
  # never reads from stdin, so detach before invoking provider CLIs.
  exec </dev/null
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

query_codex() {
  local full_prompt="$1"
  local output_file="$2"
  local log_file="$RUN_DIR/codex.log"

  if ! codex exec \
    --model "$codex_model" \
    -c "model_reasoning_effort=\"$codex_reasoning_effort\"" \
    --full-auto \
    --skip-git-repo-check \
    -o "$output_file" \
    "$full_prompt" \
    > "$log_file" \
    2>&1; then
    emit_provider_logs "codex" "$log_file"
    return 1
  fi

  emit_provider_logs "codex" "$log_file"
}

query_gemini() {
  local full_prompt="$1"
  local output_file="$2"
  local include_dir="${3:-}"
  local sandbox_args=(--sandbox)
  local log_file="$RUN_DIR/gemini.log"

  if [ -n "$include_dir" ]; then
    sandbox_args+=(--include-directories "$include_dir")
  fi

  if ! gemini \
    -p "$full_prompt" \
    -m "$gemini_model" \
    "${sandbox_args[@]}" \
    --output-format text \
    > "$output_file" \
    2> "$log_file"; then
    emit_provider_logs "gemini" "$log_file"
    return 1
  fi

  emit_provider_logs "gemini" "$log_file"
}

run_provider_query() {
  local provider_name="$1"
  local full_prompt="$2"
  local output_file="$3"
  local include_dir="${4:-}"

  case "$provider_name" in
    codex)
      if ! query_codex "$full_prompt" "$output_file"; then
        error_exit \
          "codex exec failed" \
          "Error: Codex query failed. Make sure the Codex CLI is installed and authenticated."
      fi
      ;;
    gemini)
      if ! query_gemini "$full_prompt" "$output_file" "$include_dir"; then
        error_exit \
          "gemini exec failed" \
          "Error: Gemini query failed. Make sure the Gemini CLI is installed and authenticated."
      fi
      ;;
    *)
      error_exit \
        "unknown provider: $provider_name" \
        "Error: Unknown provider '$provider_name'. Supported: codex, gemini. Check ~/.config/mid-flight/config"
      ;;
  esac
}
