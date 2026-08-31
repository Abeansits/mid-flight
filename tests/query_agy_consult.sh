#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=agy
agy_model=gemini-3.1-pro-high
agy_effort=high
EOF

write_agy_stub "agy-ok"

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
We are testing Antigravity integration.

## Question
Should MidFlight treat agy as the Google provider?
EOF
)"

output="$(run_query "$QUERY_FILE" consult)"

assert_eq "agy-ok" "$output" "consult query should return stubbed agy output"
assert_eq "gemini-3.1-pro-high" "$(cat "$TEST_DIR/agy_model.txt")" "agy should receive the configured model"
assert_eq "high" "$(cat "$TEST_DIR/agy_effort.txt")" "agy should receive the configured effort"
assert_eq "text" "$(cat "$TEST_DIR/agy_output_format.txt")" "agy should request text output"
assert_eq "no" "$(cat "$TEST_DIR/agy_skip_permissions.txt")" \
  "consult must not pass --dangerously-skip-permissions"
assert_contains "$(cat "$TEST_DIR/agy_prompt.txt")" \
  "You are a senior engineer being consulted mid-development." \
  "agy prompt should include the consult system prompt"
assert_contains "$(cat "$TEST_DIR/agy_prompt.txt")" \
  "Should MidFlight treat agy as the Google provider?" \
  "agy prompt should include the query body"

echo "PASS: consult mode routes through agy with the expected flags and prompt"
