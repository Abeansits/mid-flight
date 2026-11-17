#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=agy
EOF

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

write_agy_failure() {
  printf '%s\n' "$1" > "$TEST_DIR/agy_stderr.txt"
  cat > "$TEST_DIR/bin/agy" <<EOF
#!/bin/bash
cat "$TEST_DIR/agy_stderr.txt" >&2
exit 1
EOF
  chmod +x "$TEST_DIR/bin/agy"
}

run_failure() {
  local stdout_file="$TEST_DIR/stdout.txt"
  local status

  set +e
  run_cli "Why did the provider fail?" >"$stdout_file" 2>"$TEST_DIR/stderr.txt"
  status=$?
  set -e

  stdout="$(cat "$stdout_file")"
  assert_eq "1" "$status" "provider failure should exit 1"
}

filler_lines() {
  local i=1
  while [ "$i" -le 10 ]; do
    printf '%s\n' "filler line $i"
    i=$((i + 1))
  done
}

error_body="$(
  printf '%s\n' "error: model gemini-4-hydrogen-high is not recognized"
  filler_lines
)"
write_agy_failure "$error_body"
run_failure
assert_contains "$stdout" \
  "Error: Antigravity query failed. Details: error: model gemini-4-hydrogen-high is not recognized" \
  "stdout Error should keep the provider error line"
assert_not_contains "$stdout" "filler line 10" \
  "stdout Error should not use the log tail when an error line exists"
error_lines="$(printf '%s\n' "$stdout" | grep -c '^Error:' || true)"
assert_eq "1" "$error_lines" "stdout Error details should stay on one line"

plain_body="$(
  printf '%s\n' "preamble stays out of the tail"
  printf '%s\n' "tail alpha"
  printf '%s\n' "tail beta"
  printf '%s\n' "tail gamma"
)"
write_agy_failure "$plain_body"
run_failure
assert_contains "$stdout" \
  "Error: Antigravity query failed. Details: tail alpha tail beta tail gamma" \
  "stdout Error should keep the log tail when no error marker exists"
assert_not_contains "$stdout" "preamble stays out of the tail" \
  "stdout Error should not promote an earlier non-error line"

error_word_body="$(
  printf '%s\n' "note before the failure"
  printf '%s\n' "Error the model was rejected"
  filler_lines
)"
write_agy_failure "$error_word_body"
run_failure
assert_contains "$stdout" \
  "Error: Antigravity query failed. Details: Error the model was rejected" \
  "stdout Error should keep a line containing Error"
assert_not_contains "$stdout" "filler line 10" \
  "a later tail should not replace an Error line"

fatal_body="$(
  printf '%s\n' "usage: agy [options]"
  printf '%s\n' "fatal: model was rejected"
  filler_lines
)"
write_agy_failure "$fatal_body"
run_failure
assert_contains "$stdout" \
  "Error: Antigravity query failed. Details: fatal: model was rejected" \
  "stdout Error should keep the first fatal line"
assert_not_contains "$stdout" "usage: agy" \
  "a leading non-error line should not replace fatal"
assert_not_contains "$stdout" "filler line 10" \
  "a later tail should not replace fatal"

upper_body="$(
  printf '%s\n' "ERROR: not the marker"
  printf '%s\n' "tail alpha"
  printf '%s\n' "tail beta"
  printf '%s\n' "tail gamma"
)"
write_agy_failure "$upper_body"
run_failure
assert_contains "$stdout" \
  "Error: Antigravity query failed. Details: tail alpha tail beta tail gamma" \
  "ERROR: is not an error marker; the tail stays"
assert_not_contains "$stdout" "not the marker" \
  "uppercase ERROR: should not replace the tail"

pad=""
i=0
while [ "$i" -lt 300 ]; do
  pad="${pad}x"
  i=$((i + 1))
done
write_agy_failure "error:  two  spaces"
run_failure
assert_contains "$stdout" \
  "Error: Antigravity query failed. Details: error: two spaces" \
  "repeated spaces in the error line should collapse"
assert_not_contains "$stdout" "error:  two" \
  "repeated spaces should not survive into the stdout Error line"

write_agy_failure "error: model rejected ${pad} ENDMARKER"
run_failure
assert_contains "$stdout" "Details: error: model rejected " \
  "over-long error line should still start with the reason"
assert_not_contains "$stdout" "ENDMARKER" \
  "over-long error line should be truncated"
detail="${stdout#*Details: }"
detail="${detail%%$'\n'*}"
assert_eq "240" "${#detail}" "over-long error line should stop at 240 characters"

echo "PASS: stdout Error prefers the provider error line and otherwise keeps the tail"
