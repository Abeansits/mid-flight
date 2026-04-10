provider="codex"
codex_model="gpt-5.3-codex"
codex_reasoning_effort="high"
gemini_model="gemini-2.5-pro"

config_value() {
  local key="$1"
  local config_file="$2"

  grep "^${key}=" "$config_file" | cut -d= -f2- | tr -d '[:space:]' || true
}

load_config() {
  local config_file="${HOME}/.config/mid-flight/config"
  local value

  if [ -f "$config_file" ]; then
    value="$(config_value provider "$config_file")"
    [ -n "$value" ] && provider="$value"

    value="$(config_value codex_model "$config_file")"
    [ -n "$value" ] && codex_model="$value"

    value="$(config_value codex_reasoning_effort "$config_file")"
    [ -n "$value" ] && codex_reasoning_effort="$value"

    value="$(config_value gemini_model "$config_file")"
    [ -n "$value" ] && gemini_model="$value"

    log "config loaded: provider=$provider"
  else
    log "no config file found at $config_file, using defaults"
  fi
}

resolve_provider_for_mode() {
  local mode="$1"

  if [ "$mode" = "video" ]; then
    if [ "$provider" != "gemini" ]; then
      log "video mode: overriding provider=$provider -> gemini (video requires multimodal)"
    fi
    provider="gemini"
  fi
}

ensure_provider_available() {
  local provider_name="$1"
  local install_url=""

  if command -v "$provider_name" >/dev/null 2>&1; then
    return
  fi

  case "$provider_name" in
    codex) install_url="https://github.com/openai/codex" ;;
    gemini) install_url="https://github.com/google-gemini/gemini-cli" ;;
  esac

  error_exit \
    "'$provider_name' not found in PATH" \
    "Error: '$provider_name' CLI not found. Install it: $install_url"
}
