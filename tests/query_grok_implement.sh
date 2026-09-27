#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'CFG'
provider=grok
CFG

write_grok_stub "grok-implement-ok"

QUERY_FILE="$(
  write_query_file <<'Q'
## Context
Implement-mode permission check.

## Question
Add a hello() function to src/hello.sh.
Q
)"

output="$(run_query "$QUERY_FILE" implement)"

assert_eq "grok-implement-ok" "$output" "implement query should return stubbed grok output"
assert_eq "" "$(cat "$TEST_DIR/grok_model.txt")" "unset grok_model should omit -m"
assert_eq "yes" "$(cat "$TEST_DIR/grok_always_approve.txt")" \
  "implement must pass --always-approve so grok can write files"
assert_eq "" "$(cat "$TEST_DIR/grok_sandbox.txt")" \
  "implement must not pass --sandbox read-only"

echo "PASS: implement mode always-approves grok and omits empty -m"
