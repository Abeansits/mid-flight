#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'CFG'
provider=claude
claude_model=sonnet
CFG

write_claude_stub "claude-ok"

QUERY_FILE="$(
  write_query_file <<'Q'
## Context
We are testing Claude-as-provider integration.

## Question
Should MidFlight treat claude as a first-class provider?
Q
)"

output="$(run_query "$QUERY_FILE" consult)"

assert_eq "claude-ok" "$output" "consult query should return stubbed claude output"
assert_eq "sonnet" "$(cat "$TEST_DIR/claude_model.txt")" "claude should receive the configured model"
assert_eq "text" "$(cat "$TEST_DIR/claude_output_format.txt")" "claude should request text output"
assert_eq "no" "$(cat "$TEST_DIR/claude_skip_permissions.txt")" \
  "consult must not pass --dangerously-skip-permissions"
assert_eq "plan" "$(cat "$TEST_DIR/claude_permission_mode.txt")" \
  "consult claude permission mode should be plan"
assert_contains "$(cat "$TEST_DIR/claude_prompt.txt")" \
  "You are a senior engineer being consulted mid-development." \
  "claude prompt should include the consult system prompt"
assert_contains "$(cat "$TEST_DIR/claude_prompt.txt")" \
  "Should MidFlight treat claude as a first-class provider?" \
  "claude prompt should include the query body"

echo "PASS: consult mode routes through claude with the expected flags and prompt"
