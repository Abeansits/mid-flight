#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=gemini
gemini_model=test-gemini
EOF

write_gemini_stub "gemini-ok"

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
We are testing Gemini permissions.

## Question
Should MidFlight pass an approval mode?
EOF
)"

output="$(run_query "$QUERY_FILE" consult)"
assert_eq "gemini-ok" "$output" "consult query should return stubbed Gemini output"
assert_eq "" "$(cat "$TEST_DIR/gemini_unknown_args.txt")" \
  "consult gemini has no read-only approval flag to pass"

output="$(run_query "$QUERY_FILE" implement)"
assert_eq "gemini-ok" "$output" "implement query should return stubbed Gemini output"
assert_eq "" "$(cat "$TEST_DIR/gemini_unknown_args.txt")" \
  "implement gemini must not pass a read-only approval flag"
assert_contains "$(cat "$TEST_DIR/gemini_prompt.txt")" \
  "implementation" \
  "implement prompt should include the implement system prompt"

echo "PASS: gemini consult and implement pass no approval-mode flag"
