#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
codex_model=test-model
EOF

write_codex_stub "passthrough-ok"

QUERY_FILE="$TEST_DIR/prebuilt.md"
cat > "$QUERY_FILE" <<'EOF'
PREBUILT-SENTINEL: this exact body was authored by the caller.
EOF

output="$(run_cli --query-file "$QUERY_FILE")"

assert_eq "passthrough-ok" "$output" "query-file run should return the stubbed response"

prompt="$(cat "$TEST_DIR/codex_prompt.txt")"
assert_contains "$prompt" "PREBUILT-SENTINEL: this exact body was authored by the caller." \
  "query-file contents should pass through untouched"

if [[ "$prompt" == *"## Question"* ]]; then
  echo "FAIL: --query-file should not be wrapped in a generated Question section" >&2
  exit 1
fi

# Combining --query-file with an inline question is a usage error.
set +e
err_output="$(run_cli --query-file "$QUERY_FILE" "an extra question" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "--query-file plus inline question should exit 2"
assert_contains "$err_output" "cannot be combined" \
  "--query-file plus inline question should explain the conflict"

echo "PASS: --query-file passes through and rejects conflicting inline input"
