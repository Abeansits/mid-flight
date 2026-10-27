#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

reset_fm_logs() {
  rm -f \
    "$TEST_DIR/fm_commands.txt" \
    "$TEST_DIR/fm_prompt.txt" \
    "$TEST_DIR/fm_model.txt" \
    "$TEST_DIR/fm_token_count_prompt.txt" \
    "$TEST_DIR/fm_token_count_quiet.txt"
}

assert_no_exact_command() {
  local command_name="$1"
  local message="$2"
  if [ -f "$TEST_DIR/fm_commands.txt" ] && grep -qx "$command_name" "$TEST_DIR/fm_commands.txt"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

write_config <<'EOF'
provider=codex
codex_model=test-model
EOF

write_fm_stub "fm-reply" "12"
output="$(run_cli -p fm "should we keep the cache?")"

assert_eq "fm-reply" "$output" "consult should print the fm reply"
assert_contains "$(cat "$TEST_DIR/fm_prompt.txt")" "should we keep the cache?" \
  "fm respond should receive the question"
assert_contains "$(cat "$TEST_DIR/fm_prompt.txt")" \
  "You are a senior engineer being consulted mid-development." \
  "fm respond should receive the consult instructions"
assert_eq "$(cat "$TEST_DIR/fm_token_count_prompt.txt")" "$(cat "$TEST_DIR/fm_prompt.txt")" \
  "count-tokens should see the same prompt fm respond receives"
assert_eq "yes" "$(cat "$TEST_DIR/fm_token_count_quiet.txt")" \
  "count-tokens should be called with -q"
assert_eq "" "$(cat "$TEST_DIR/fm_model.txt")" "unset model should omit --model"
assert_contains "$(cat "$TEST_DIR/fm_commands.txt")" "count-tokens" \
  "on-device consult should count tokens"
assert_no_exact_command "token-count" \
  "a working count-tokens must not fall back to token-count"
assert_contains "$(cat "$TEST_DIR/fm_commands.txt")" "respond" \
  "on-device consult should then respond"

# Exactly the input budget still runs. The cutoff is strictly greater than 3072.
reset_fm_logs
write_fm_stub "at-limit" "3072"
output="$(run_cli -p fm "at the budget")"
assert_eq "at-limit" "$output" "3072 tokens should still call fm"

reset_fm_logs
write_fm_stub "system-reply" "15"
output="$(run_cli -p fm --model system "on device please")"
assert_eq "system-reply" "$output" "--model system should return the fm reply"
assert_eq "system" "$(cat "$TEST_DIR/fm_model.txt")" "--model system should pass through"
assert_contains "$(cat "$TEST_DIR/fm_commands.txt")" "count-tokens" \
  "--model system should preflight count-tokens"
assert_no_exact_command "token-count" \
  "--model system should not fall back when count-tokens works"

reset_fm_logs
write_fm_stub "pcc-reply" "99999"
output="$(run_cli -p fm --model pcc "use private cloud")"
assert_eq "pcc-reply" "$output" "--model pcc should return the fm reply"
assert_eq "pcc" "$(cat "$TEST_DIR/fm_model.txt")" "--model pcc should pass through"
assert_contains "$(cat "$TEST_DIR/fm_commands.txt")" "respond" \
  "--model pcc should call respond"
assert_no_exact_command "count-tokens" "--model pcc must not run count-tokens"
assert_no_exact_command "token-count" "--model pcc must not run token-count"
if [ -f "$TEST_DIR/fm_token_count_prompt.txt" ]; then
  echo "FAIL: --model pcc must not preflight a token count" >&2
  exit 1
fi

reset_fm_logs
write_fm_stub "should-not-print" "count is 3073 tokens"
set +e
output="$(run_cli -p fm "this prompt is too long" 2>"$TEST_DIR/over_err.txt")"
status=$?
set -e
assert_eq "1" "$status" "over-limit fm prompt should exit 1"
assert_contains "$output" "the prompt is 3073 tokens" "over-limit error should report the count"
assert_contains "$output" "3072" "over-limit error should state the 3072 threshold"
assert_contains "$output" "4096-token window" "over-limit error should mention the 4096 window"
assert_contains "$output" "Shorten the question or use another provider" \
  "over-limit error should say how to recover"
if [ -f "$TEST_DIR/fm_prompt.txt" ]; then
  echo "FAIL: over-limit fm must not call respond" >&2
  exit 1
fi
assert_contains "$(cat "$TEST_DIR/fm_token_count_prompt.txt")" "this prompt is too long" \
  "over-limit check should count the question"
assert_contains "$(cat "$TEST_DIR/fm_token_count_prompt.txt")" \
  "You are a senior engineer being consulted mid-development." \
  "over-limit check should count the consult instructions"

reset_fm_logs
write_fm_stub "continued" "not a number"
output="$(run_cli -p fm "unparseable count")"
assert_eq "continued" "$output" "unparseable token-count should still call fm"
assert_contains "$(cat "$TEST_DIR/fm_prompt.txt")" "unparseable count" \
  "unparseable token-count should still deliver the prompt"

reset_fm_logs
write_fm_stub "continued-anyway" "99999" "0" "1"
output="$(run_cli -p fm "count command failed")"
assert_eq "continued-anyway" "$output" "a failing count-tokens should not block fm"
assert_contains "$(cat "$TEST_DIR/fm_prompt.txt")" "count command failed" \
  "a failing count-tokens should still deliver the prompt"
assert_no_exact_command "token-count" \
  "a failing count-tokens must not try token-count"

# implement is refused before fm runs.
reset_fm_logs
set +e
run_cli -m implement -p fm "ship the change" >"$TEST_DIR/impl_out.txt" 2>"$TEST_DIR/impl_err.txt"
status=$?
set -e
assert_eq "2" "$status" "-p fm implement should exit 2"
assert_eq "" "$(cat "$TEST_DIR/impl_out.txt")" "implement refusal should leave stdout empty"
assert_contains "$(cat "$TEST_DIR/impl_err.txt")" \
  "fm is consult-only (no repo access); use -m consult" \
  "implement refusal should say fm is consult-only"
if [ -f "$TEST_DIR/fm_commands.txt" ]; then
  echo "FAIL: implement must not invoke fm" >&2
  exit 1
fi

write_config <<'EOF'
provider=fm
EOF
set +e
run_cli -m implement "ship from config" >"$TEST_DIR/impl_cfg_out.txt" 2>"$TEST_DIR/impl_cfg_err.txt"
status=$?
set -e
assert_eq "2" "$status" "config provider=fm implement should exit 2"
assert_contains "$(cat "$TEST_DIR/impl_cfg_err.txt")" \
  "fm is consult-only (no repo access); use -m consult" \
  "config implement refusal should say fm is consult-only"

# Engine path (query.sh) refuses too, for callers that skip the CLI.
QUERY_FILE="$(
  write_query_file <<'EOF'
## Question
Change the cache.
EOF
)"
set +e
run_query "$QUERY_FILE" implement >"$TEST_DIR/impl_engine_out.txt" 2>"$TEST_DIR/impl_engine_err.txt"
status=$?
set -e
assert_eq "2" "$status" "query.sh implement with fm should exit 2"
assert_contains "$(cat "$TEST_DIR/impl_engine_err.txt")" \
  "fm is consult-only (no repo access); use -m consult" \
  "query.sh implement refusal should say fm is consult-only"

# --video / --video-gen keep the usual non-capable routing.
write_config <<'EOF'
provider=fm
gemini_model=test-gemini
EOF
write_gemini_stub "video-from-gemini"
printf 'fake-video-bytes\n' > "$TEST_DIR/clip.mp4"
output="$(run_cli --video "$TEST_DIR/clip.mp4" "what is in this clip?")"
assert_eq "video-from-gemini" "$output" "provider=fm --video should retarget to gemini"

set +e
err="$(run_cli -p fm --video-gen "a paper plane" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "-p fm --video-gen should exit 2"
assert_contains "$err" "--video-gen supports grok" \
  "-p fm --video-gen should keep the grok-only refusal"

set +e
err="$(run_cli -p fm --image-gen "a paper plane" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "-p fm --image-gen should exit 2"
assert_contains "$err" "--image-gen supports codex and grok" \
  "-p fm --image-gen should keep the image-gen refusal"

# Missing binary, then license / availability failures, then a plain context error.
write_config <<'EOF'
provider=codex
EOF
rm -f "$TEST_DIR/bin/fm"
set +e
output="$(run_cli -p fm "where is the bug?" 2>"$TEST_DIR/missing_err.txt")"
status=$?
set -e
assert_eq "1" "$status" "missing fm should exit 1"
assert_contains "$output" "requires macOS 27" "missing fm should mention macOS 27"
assert_contains "$output" "sudo fm license" "missing fm should mention sudo fm license"
assert_contains "$output" "fm available" "missing fm should mention fm available"
if [[ "$output" == *"fm models"* ]]; then
  echo "FAIL: missing fm must not mention fm models" >&2
  exit 1
fi

write_fm_failure() {
  local stderr_line="$1"
  cat > "$TEST_DIR/bin/fm" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "$stderr_line" >&2
exit 1
EOF
  chmod +x "$TEST_DIR/bin/fm"
}

esc="$(printf '\033')"
write_fm_failure "${esc}[31mfm is not licensed${esc}[0m"
set +e
output="$(run_cli -p fm "license check" 2>/dev/null)"
status=$?
set -e
assert_eq "1" "$status" "unlicensed fm should exit 1"
assert_contains "$output" "sudo fm license" "unlicensed fm should mention sudo fm license"
assert_contains "$output" "fm available" "unlicensed fm should mention fm available"
assert_contains "$output" "fm is not licensed" "unlicensed fm should quote the plain error"
if [[ "$output" == *"$esc"* ]]; then
  echo "FAIL: fm error text must drop ANSI color codes" >&2
  exit 1
fi
if [[ "$output" == *"fm models"* ]]; then
  echo "FAIL: unlicensed fm must not mention fm models" >&2
  exit 1
fi

write_fm_failure "fm: model unavailable"
set +e
output="$(run_cli -p fm "availability check" 2>/dev/null)"
status=$?
set -e
assert_eq "1" "$status" "unavailable fm model should exit 1"
assert_contains "$output" "requires macOS 27" "unavailable model should mention macOS 27"
assert_contains "$output" "fm available" "unavailable model should mention fm available"

write_fm_failure "service unavailable"
set +e
output="$(run_cli -p fm "generic unavailable" 2>/dev/null)"
status=$?
set -e
assert_eq "1" "$status" "generic unavailable should exit 1"
assert_contains "$output" "Error: fm query failed." "generic unavailable should stay a query failure"
if [[ "$output" == *"sudo fm license"* ]]; then
  echo "FAIL: generic unavailable must not be rewritten as a license error" >&2
  exit 1
fi

write_fm_failure "notes.md: no such file or directory"
set +e
output="$(run_cli -p fm "missing notes" 2>/dev/null)"
status=$?
set -e
assert_eq "1" "$status" "a generic missing-file error should exit 1"
assert_contains "$output" "Error: fm query failed." "a generic missing file should stay a query failure"
if [[ "$output" == *"sudo fm license"* ]]; then
  echo "FAIL: a generic missing file must not be rewritten as a license error" >&2
  exit 1
fi

write_fm_failure "prompt exceeds context size"
set +e
output="$(run_cli -p fm "context from fm" 2>/dev/null)"
status=$?
set -e
assert_eq "1" "$status" "fm context error should exit 1"
assert_contains "$output" "Error: fm query failed." "fm context error should use the query-failed path"
assert_contains "$output" "prompt exceeds context size" "fm context error should be quoted"
if [[ "$output" == *"sudo fm license"* ]]; then
  echo "FAIL: a context-size error must not be rewritten as a license error" >&2
  exit 1
fi

# macOS 27.0 rejects --model pcc. The error is the first stderr line; usage follows.
reset_fm_logs
pcc_stderr="$(printf '%s\n' \
  "Error: The value 'pcc' is invalid for '--model <model>'. Please provide one of 'system'." \
  "OVERVIEW: Run a prompt against the on-device model." \
  "USAGE: fm respond --model <model> <prompt>" \
  "OPTIONS:" \
  "  --model <model>  Model name.")"
write_fm_stub "rejected" "12" "0" "0" "$pcc_stderr" "64"
set +e
output="$(run_cli -p fm --model pcc "rejected cloud" 2>/dev/null)"
status=$?
set -e
assert_eq "1" "$status" "invalid pcc should exit 1"
assert_contains "$output" "Error: fm query failed." "invalid pcc should use the query-failed path"
assert_contains "$output" "Error: The value 'pcc' is invalid for '--model <model>'. Please provide one of 'system'." \
  "invalid pcc should keep fm's first error line"
if [[ "$output" == *"OVERVIEW:"* ]]; then
  echo "FAIL: invalid pcc details must not keep the usage tail" >&2
  exit 1
fi
assert_eq "pcc" "$(cat "$TEST_DIR/fm_model.txt")" \
  "invalid pcc should still pass --model through"
if [[ "$output" == *"sudo fm license"* ]]; then
  echo "FAIL: invalid pcc must not be rewritten as a license error" >&2
  exit 1
fi
assert_no_exact_command "count-tokens" "invalid pcc must not preflight count-tokens"
assert_no_exact_command "token-count" "invalid pcc must not preflight token-count"

write_codex_stub "codex says yes"
write_fm_stub "fm says no" "8"
output="$(run_cli --providers codex,fm "dual question")"
assert_contains "$output" "## Provider A: Codex" "dual should label Codex"
assert_contains "$output" "## Provider B: fm" "dual should label fm"
assert_contains "$output" "codex says yes" "dual should print the Codex reply"
assert_contains "$output" "fm says no" "dual should print the fm reply"
assert_contains "$(cat "$TEST_DIR/fm_prompt.txt")" "dual question" \
  "dual should send the question to fm"

write_config <<'EOF'
provider=codex
codex_model=test-model
EOF
write_codex_stub "primary ok"
write_fm_stub "partner ok" "9"
output="$(run_cli --dual fm "partner question")"
assert_contains "$output" "## Provider A: Codex" "--dual fm should keep the configured primary"
assert_contains "$output" "## Provider B: fm" "--dual fm should label the partner"
assert_contains "$output" "partner ok" "--dual fm should print the fm reply"

echo "PASS: fm consult, token preflight, consult-only refusal, and dual-consult"
