#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=antigravity
agy_model=gemini-3.1-pro-high
EOF

write_agy_stub "alias-ok"

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
Alias check.

## Question
Does provider=antigravity call agy?
EOF
)"

output="$(run_query "$QUERY_FILE" consult)"

assert_eq "alias-ok" "$output" "provider=antigravity should invoke the agy binary"
assert_eq "gemini-3.1-pro-high" "$(cat "$TEST_DIR/agy_model.txt")" \
  "antigravity alias should still honor agy_model"

echo "PASS: provider=antigravity normalizes to agy"
