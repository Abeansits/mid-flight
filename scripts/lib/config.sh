# shellcheck shell=bash disable=SC2034

provider="codex"
codex_model="gpt-5.3-codex"
codex_reasoning_effort="high"
gemini_model="gemini-2.5-pro"
opencode_model=""
opencode_variant="high"
opencode_format="default"
oz_model="auto"
oz_output_format="text"
oz_profile=""
CONFIG_VALIDATION_ISSUES=()

config_file_path() {
  printf '%s\n' "${HOME}/.config/mid-flight/config"
}

reset_config_validation_issues() {
  CONFIG_VALIDATION_ISSUES=()
}

add_config_validation_issue() {
  CONFIG_VALIDATION_ISSUES+=("$1")
}

has_config_validation_issues() {
  [ "${#CONFIG_VALIDATION_ISSUES[@]}" -gt 0 ]
}

format_config_validation_issues() {
  local issue

  for issue in "${CONFIG_VALIDATION_ISSUES[@]}"; do
    printf '%s\n' "$issue"
  done
}

supported_config_key() {
  case "$1" in
    provider|codex_model|codex_reasoning_effort|gemini_model|opencode_model|opencode_variant|opencode_format|oz_model|oz_output_format|oz_profile)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

config_value() {
  local key="$1"
  local config_file="$2"

  grep "^${key}=" "$config_file" | cut -d= -f2- | tr -d '[:space:]' || true
}

load_config() {
  local config_file
  local value

  config_file="$(config_file_path)"

  if [ -f "$config_file" ]; then
    value="$(config_value provider "$config_file")"
    [ -n "$value" ] && provider="$value"

    value="$(config_value codex_model "$config_file")"
    [ -n "$value" ] && codex_model="$value"

    value="$(config_value codex_reasoning_effort "$config_file")"
    [ -n "$value" ] && codex_reasoning_effort="$value"

    value="$(config_value gemini_model "$config_file")"
    [ -n "$value" ] && gemini_model="$value"

    value="$(config_value opencode_model "$config_file")"
    [ -n "$value" ] && opencode_model="$value"

    value="$(config_value opencode_variant "$config_file")"
    [ -n "$value" ] && opencode_variant="$value"

    value="$(config_value opencode_format "$config_file")"
    [ -n "$value" ] && opencode_format="$value"

    value="$(config_value oz_model "$config_file")"
    [ -n "$value" ] && oz_model="$value"

    value="$(config_value oz_output_format "$config_file")"
    [ -n "$value" ] && oz_output_format="$value"

    value="$(config_value oz_profile "$config_file")"
    [ -n "$value" ] && oz_profile="$value"

    log "config loaded: provider=$provider"
  else
    log "no config file found at $config_file, using defaults"
  fi
}

validate_config_file_syntax() {
  local config_file="$1"
  local line_number=0
  local line=""
  local key=""

  if [ ! -f "$config_file" ]; then
    return 0
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    line_number=$((line_number + 1))

    case "$line" in
      ""|"#"*) continue ;;
    esac

    if [[ ! "$line" =~ ^[A-Za-z0-9_]+=.*$ ]]; then
      add_config_validation_issue "Invalid config syntax at line $line_number. Use key=value with no spaces around '='."
      continue
    fi

    key="${line%%=*}"

    if ! supported_config_key "$key"; then
      add_config_validation_issue "Unknown config key '$key' at line $line_number."
    fi
  done < "$config_file"
}

validate_loaded_config() {
  case "$provider" in
    codex|gemini|opencode|oz) ;;
    *)
      add_config_validation_issue "Unsupported provider '$provider'. Supported providers: codex, gemini, opencode, oz."
      ;;
  esac

  if [ -z "$codex_model" ]; then
    add_config_validation_issue "codex_model cannot be empty."
  fi

  case "$codex_reasoning_effort" in
    low|medium|high|xhigh) ;;
    *)
      add_config_validation_issue "Unsupported codex_reasoning_effort '$codex_reasoning_effort'. Use low, medium, high, or xhigh."
      ;;
  esac

  if [ -z "$gemini_model" ]; then
    add_config_validation_issue "gemini_model cannot be empty."
  fi

  case "$opencode_format" in
    default|json) ;;
    *)
      add_config_validation_issue "Unsupported opencode_format '$opencode_format'. Use default or json."
      ;;
  esac

  if [ -z "$oz_model" ]; then
    add_config_validation_issue "oz_model cannot be empty."
  fi

  case "$oz_output_format" in
    text|pretty|json) ;;
    *)
      add_config_validation_issue "Unsupported oz_output_format '$oz_output_format'. Use text, pretty, or json."
      ;;
  esac
}

validate_config_state() {
  local config_file

  config_file="$(config_file_path)"
  reset_config_validation_issues
  validate_config_file_syntax "$config_file"
  validate_loaded_config

  if has_config_validation_issues; then
    return 1
  fi

  return 0
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
    opencode) install_url="https://opencode.ai/docs/cli/" ;;
    oz) install_url="https://docs.warp.dev/reference/cli/cli" ;;
  esac

  error_exit \
    "'$provider_name' not found in PATH" \
    "Error: '$provider_name' CLI not found. Install it: $install_url"
}
