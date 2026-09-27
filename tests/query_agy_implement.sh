#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=agy
EOF

write_agy_stub "agy-implement-ok"

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
Implement-mode permission check.

## Question
Add a hello() function to src/hello.sh.
EOF
)"

output="$(run_query "$QUERY_FILE" implement)"

assert_eq "agy-implement-ok" "$output" "implement query should return stubbed agy output"
assert_eq "" "$(cat "$TEST_DIR/agy_model.txt")" "unset agy_model should omit --model"
assert_eq "yes" "$(cat "$TEST_DIR/agy_skip_permissions.txt")" \
  "implement must pass --dangerously-skip-permissions so agy can write files"
assert_eq "" "$(cat "$TEST_DIR/agy_unknown_args.txt")" \
  "implement agy must not pass a read-only flag"

echo "PASS: implement mode skips agy permissions and omits empty --model"
