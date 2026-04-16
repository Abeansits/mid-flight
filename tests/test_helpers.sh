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

run_check_config() {
  bash "$ROOT_DIR/scripts/check-config.sh" "$@"
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
