#!/bin/bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR=""
ORIGINAL_PATH="$PATH"

setup_test_env() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/midflight-test.XXXXXX")"
  mkdir -p "$TEST_DIR/bin" "$TEST_DIR/home/.config/mid-flight"

  export TEST_DIR
  export HOME="$TEST_DIR/home"
  export PATH="$TEST_DIR/bin:/usr/bin:/bin"
}

cleanup_test_env() {
  if [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi

  export PATH="$ORIGINAL_PATH"
}

write_config() {
  cat > "$HOME/.config/mid-flight/config"
}

write_query_file() {
  local path="$TEST_DIR/query.md"

  cat > "$path"
  printf '%s\n' "$path"
}

run_query() {
  bash "$ROOT_DIR/scripts/query.sh" "$@"
}

run_cli() {
  bash "$ROOT_DIR/bin/midflight" "$@"
}

run_check_config() {
  bash "$ROOT_DIR/scripts/check-config.sh" "$@"
}

# Stub the codex CLI: capture the prompt to $TEST_DIR/codex_prompt.txt and
# write a canned response. Optional arg overrides the response text.
write_codex_stub() {
  local response="${1:-stub-codex-ok}"

  cat > "$TEST_DIR/bin/codex" <<EOF
#!/bin/bash
set -euo pipefail
output_file=""
prompt=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o|--output-last-message) output_file="\$2"; shift 2 ;;
    --model|-c|--sandbox) shift 2 ;;
    --skip-git-repo-check) shift ;;
    *) prompt="\$1"; shift ;;
  esac
done
printf '%s' "\$prompt" > "$TEST_DIR/codex_prompt.txt"
printf '%s\n' "$response" > "\$output_file"
EOF
  chmod +x "$TEST_DIR/bin/codex"
}

# Stub the gemini CLI: capture the prompt to $TEST_DIR/gemini_prompt.txt and
# write a canned response to stdout. Optional arg overrides the response text.
write_gemini_stub() {
  local response="${1:-stub-gemini-ok}"

  cat > "$TEST_DIR/bin/gemini" <<EOF
#!/bin/bash
set -euo pipefail
prompt=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -p) prompt="\$2"; shift 2 ;;
    -m|--include-directories) shift 2 ;;
    --output-format) shift 2 ;;
    *) shift ;;
  esac
done
printf '%s' "\$prompt" > "$TEST_DIR/gemini_prompt.txt"
printf '%s\n' "$response"
EOF
  chmod +x "$TEST_DIR/bin/gemini"
}

# Stub the agy CLI: capture prompt/flags and print a canned response.
# Optional arg overrides the response text.
write_agy_stub() {
  local response="${1:-stub-agy-ok}"

  cat > "$TEST_DIR/bin/agy" <<EOF
#!/bin/bash
set -euo pipefail
prompt=""
model=""
effort=""
add_dir=""
skip_permissions="no"
output_format=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -p|--print|--prompt) prompt="\$2"; shift 2 ;;
    --model) model="\$2"; shift 2 ;;
    --effort) effort="\$2"; shift 2 ;;
    --add-dir) add_dir="\$2"; shift 2 ;;
    --output-format) output_format="\$2"; shift 2 ;;
    --dangerously-skip-permissions) skip_permissions="yes"; shift ;;
    *) shift ;;
  esac
done
printf '%s' "\$prompt" > "$TEST_DIR/agy_prompt.txt"
printf '%s' "\$model" > "$TEST_DIR/agy_model.txt"
printf '%s' "\$effort" > "$TEST_DIR/agy_effort.txt"
printf '%s' "\$add_dir" > "$TEST_DIR/agy_add_dir.txt"
printf '%s' "\$output_format" > "$TEST_DIR/agy_output_format.txt"
printf '%s' "\$skip_permissions" > "$TEST_DIR/agy_skip_permissions.txt"
printf '%s\n' "$response"
EOF
  chmod +x "$TEST_DIR/bin/agy"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" != "$actual" ]; then
    echo "FAIL: $message" >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: $message" >&2
    echo "Missing: $needle" >&2
    exit 1
  fi
}
