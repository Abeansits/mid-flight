#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    echo "FAIL: $message" >&2
    echo "Unexpected: $needle" >&2
    exit 1
  fi
}

write_exploding_stub() {
  local command_name="$1"

  cat > "$TEST_DIR/bin/$command_name" <<'EOF'
#!/bin/bash
echo "provider exploded" >&2
exit 1
EOF
  chmod +x "$TEST_DIR/bin/$command_name"
}

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
We are testing unrecognized provider failures.

## Question
What happened?
EOF
)"

assert_unrecognized() {
  local provider_name="$1"
  local command_name="$2"
  local display_name="$3"
  local output
  local status

  printf 'provider=%s\n' "$provider_name" > "$HOME/.config/mid-flight/config"
  write_exploding_stub "$command_name"

  set +e
  output="$(run_query "$QUERY_FILE" consult 2>&1)"
  status=$?
  set -e

  assert_eq "1" "$status" "$display_name unrecognized failure should exit 1"
  assert_contains "$output" "Error: ${display_name} query failed. Details: provider exploded" \
    "$display_name unrecognized failure should keep the provider's last line"
  assert_not_contains "$output" "installed" \
    "$display_name unrecognized failure should not say installed"
  assert_not_contains "$output" "authenticated" \
    "$display_name unrecognized failure should not say authenticated"
}

assert_unrecognized codex codex Codex
assert_unrecognized gemini gemini Gemini
assert_unrecognized agy agy Antigravity
assert_unrecognized opencode opencode OpenCode
assert_unrecognized oz oz Oz
assert_unrecognized grok grok Grok
assert_unrecognized claude claude Claude

printf 'provider=%s\n' "codex" > "$HOME/.config/mid-flight/config"
cat > "$TEST_DIR/bin/codex" <<'EOF'
#!/bin/bash
echo "permission denied" >&2
exit 1
EOF
chmod +x "$TEST_DIR/bin/codex"

set +e
output="$(run_query "$QUERY_FILE" consult 2>&1)"
status=$?
set -e

assert_eq "1" "$status" "permission denied should still exit 1"
assert_contains "$output" "Error: Codex query failed. Details: permission denied" \
  "permission denied should stay an unrecognized failure"
assert_not_contains "$output" "authentication failed" \
  "permission denied must not be labeled an auth failure"
assert_not_contains "$output" "Re-authenticate" \
  "permission denied must not tell the next agent to re-authenticate"
assert_not_contains "$output" "installed" \
  "permission denied should not say installed"
assert_not_contains "$output" "authenticated" \
  "permission denied should not say authenticated"

TIMEOUT_QUERY="$(
  write_query_file <<'EOF'
## Context
Codex stores the question in its log.

## Question
What is the timeout for this request?
EOF
)"

cat > "$TEST_DIR/bin/codex" <<'EOF'
#!/bin/bash
set -euo pipefail
prompt=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output-last-message) shift 2 ;;
    --model|-c|--sandbox) shift 2 ;;
    --skip-git-repo-check) shift ;;
    *) prompt="$1"; shift ;;
  esac
done
printf '%s\n' "$prompt"
printf '%s\n' "provider exploded"
printf '%s\n' "no match alpha"
printf '%s\n' "no match beta"
exit 1
EOF
chmod +x "$TEST_DIR/bin/codex"

set +e
output="$(run_query "$TIMEOUT_QUERY" consult 2>&1)"
status=$?
set -e

assert_eq "1" "$status" "timeout in the question should still exit 1"
assert_contains "$output" "What is the timeout for this request?" \
  "the question text should be present in the captured Codex log"
assert_contains "$output" "Error: Codex query failed. Details: provider exploded no match alpha no match beta" \
  "last three lines should be the details, not the question"
assert_not_contains "$output" "failed because of a network issue" \
  "timeout in the question must not label the run a network error"
assert_not_contains "$output" "network error" \
  "timeout in the question must not be logged as a network error"
assert_not_contains "$output" "installed" \
  "unrecognized failure after a timeout question should not say installed"
assert_not_contains "$output" "authenticated" \
  "unrecognized failure after a timeout question should not say authenticated"

# Error marker early in a noisy log (e.g. error: followed by 10+ model lines)
# should surface in stdout Details instead of being pushed out by the tail.
printf 'provider=%s\n' "agy" > "$HOME/.config/mid-flight/config"
cat > "$TEST_DIR/bin/agy" <<'EOF'
#!/bin/bash
printf '%s\n' 'error: invalid model selection: model gemini-4-hydrogen-high is not recognized' >&2
printf '%s\n' 'Available models:' >&2
for i in 1 2 3 4 5 6 7 8 9 10; do
  printf '  Model Option %d   (Thinking)\n' "$i" >&2
done
exit 1
EOF
chmod +x "$TEST_DIR/bin/agy"

set +e
stdout_only="$(run_query "$QUERY_FILE" consult 2>/dev/null)"
status=$?
set -e

assert_eq "1" "$status" "agy invalid model failure should exit 1"
assert_contains "$stdout_only" "Error: Antigravity query failed. Details: error: invalid model selection: model gemini-4-hydrogen-high is not recognized" \
  "stdout Error should carry the first error: line rather than the model list tail"
assert_not_contains "$stdout_only" "Model Option 10" \
  "stdout Error should not fall back to the model list tail when an error line matched"

# Also check Error and fatal markers followed by ten lines.
for marker_line in "Error: workspace quota check failed" "fatal: unable to reach backend"; do
  printf '%s\n' "$marker_line" > "$TEST_DIR/marker_line.txt"
  cat > "$TEST_DIR/bin/agy" <<EOF
#!/bin/bash
cat "$TEST_DIR/marker_line.txt" >&2
for i in 1 2 3 4 5 6 7 8 9 10; do
  printf '  trailing line %d\n' "\$i" >&2
done
exit 1
EOF
  chmod +x "$TEST_DIR/bin/agy"

  set +e
  stdout_only="$(run_query "$QUERY_FILE" consult 2>/dev/null)"
  status=$?
  set -e

  assert_eq "1" "$status" "marker failure ($marker_line) should exit 1"
  assert_contains "$stdout_only" "Details: $marker_line" \
    "stdout Error should surface '$marker_line'"
done

# All-caps ERROR: is not one of the case-sensitive markers and keeps the tail.
cat > "$TEST_DIR/bin/agy" <<'EOF'
#!/bin/bash
printf '%s\n' 'ERROR: uppercase should not match' >&2
printf '%s\n' 'tail alpha' >&2
printf '%s\n' 'tail beta' >&2
printf '%s\n' 'tail gamma' >&2
exit 1
EOF
chmod +x "$TEST_DIR/bin/agy"

set +e
stdout_only="$(run_query "$QUERY_FILE" consult 2>/dev/null)"
status=$?
set -e

assert_eq "1" "$status" "uppercase ERROR failure should exit 1"
assert_contains "$stdout_only" "Details: tail alpha tail beta tail gamma" \
  "uppercase ERROR: should fall back to the log tail"
assert_not_contains "$stdout_only" "uppercase should not match" \
  "uppercase ERROR: should not replace the log tail"

# Over-long matched line is capped at 240 characters.
pad=""
i=0
while [ "$i" -lt 260 ]; do
  pad="${pad}x"
  i=$((i + 1))
done
printf 'error: long reason %s ENDMARKER\n' "$pad" > "$TEST_DIR/long_error.txt"
cat > "$TEST_DIR/bin/agy" <<EOF
#!/bin/bash
cat "$TEST_DIR/long_error.txt" >&2
exit 1
EOF
chmod +x "$TEST_DIR/bin/agy"

set +e
stdout_only="$(run_query "$QUERY_FILE" consult 2>/dev/null)"
status=$?
set -e

assert_eq "1" "$status" "over-long error failure should exit 1"
assert_contains "$stdout_only" "Details: error: long reason " \
  "over-long error line should preserve the beginning of the reason"
assert_not_contains "$stdout_only" "ENDMARKER" \
  "over-long error line should be truncated at 240 characters"
detail="${stdout_only#*Details: }"
detail="${detail%%$'\n'*}"
assert_eq "240" "${#detail}" "over-long Details excerpt should stop at 240 characters"

echo "PASS: unrecognized provider failures keep the excerpt and skip install/login"
