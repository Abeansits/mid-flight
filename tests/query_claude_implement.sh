#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'CFG'
provider=claude
CFG

write_claude_stub "claude-implement-ok"

QUERY_FILE="$(
  write_query_file <<'Q'
## Context
Implement-mode permission check.

## Question
Add a hello() function to src/hello.sh.
Q
)"

output="$(run_query "$QUERY_FILE" implement)"

assert_eq "claude-implement-ok" "$output" "implement query should return stubbed claude output"
assert_eq "" "$(cat "$TEST_DIR/claude_model.txt")" "unset claude_model should omit --model"
assert_eq "yes" "$(cat "$TEST_DIR/claude_skip_permissions.txt")" \
  "implement must pass --dangerously-skip-permissions so claude can write files"
assert_eq "" "$(cat "$TEST_DIR/claude_permission_mode.txt")" \
  "implement must not pass --permission-mode plan"

echo "PASS: implement mode skips claude permissions and omits empty --model"
