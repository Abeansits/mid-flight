#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'CFG'
provider=codex
codex_model=test-model
CFG

write_codex_stub "should-not-run"
write_grok_stub "grok-ok"
write_claude_stub "claude-ok"

output="$(run_cli -p grok "Which provider answered?")"
assert_eq "grok-ok" "$output" "-p grok should route to grok"
if [ -f "$TEST_DIR/codex_prompt.txt" ]; then
  echo "FAIL: codex should not have been invoked when -p grok is set" >&2
  exit 1
fi
assert_contains "$(cat "$TEST_DIR/grok_prompt.txt")" "Which provider answered?" \
  "grok should receive the question"

output="$(run_cli -p claude "Claude take please")"
assert_eq "claude-ok" "$output" "-p claude should route to claude"
assert_contains "$(cat "$TEST_DIR/claude_prompt.txt")" "Claude take please" \
  "claude should receive the question"

output="$(run_cli -p grok-build "Alias route")"
assert_eq "grok-ok" "$output" "-p grok-build should normalize to grok"

echo "PASS: -p overrides to grok/claude (and grok-build alias)"
