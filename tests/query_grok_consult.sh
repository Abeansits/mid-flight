#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'CFG'
provider=grok
grok_model=grok-4
grok_effort=high
CFG

write_grok_stub "grok-ok"

QUERY_FILE="$(
  write_query_file <<'Q'
## Context
We are testing Grok integration.

## Question
Should MidFlight treat grok as a first-class provider?
Q
)"

output="$(run_query "$QUERY_FILE" consult)"

assert_eq "grok-ok" "$output" "consult query should return stubbed grok output"
assert_eq "grok-4" "$(cat "$TEST_DIR/grok_model.txt")" "grok should receive the configured model"
assert_eq "high" "$(cat "$TEST_DIR/grok_effort.txt")" "grok should receive the configured effort"
assert_eq "plain" "$(cat "$TEST_DIR/grok_output_format.txt")" "grok should request plain output"
assert_eq "no" "$(cat "$TEST_DIR/grok_always_approve.txt")" \
  "consult must not pass --always-approve"
assert_contains "$(cat "$TEST_DIR/grok_prompt.txt")" \
  "You are a senior engineer being consulted mid-development." \
  "grok prompt should include the consult system prompt"
assert_contains "$(cat "$TEST_DIR/grok_prompt.txt")" \
  "Should MidFlight treat grok as a first-class provider?" \
  "grok prompt should include the query body"

echo "PASS: consult mode routes through grok with the expected flags and prompt"
