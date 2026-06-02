#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

# Default config selects codex; -c points the engine at an alternate config.
write_config <<'EOF'
provider=codex
codex_model=test-model
EOF

write_codex_stub "should-not-run"
write_gemini_stub "alt-config-ok"

cat > "$TEST_DIR/alt-config" <<'EOF'
provider=gemini
gemini_model=test-gemini
EOF

output="$(run_cli -c "$TEST_DIR/alt-config" "Which config won?")"

assert_eq "alt-config-ok" "$output" "-c should route through the alternate config's provider"

if [ -f "$TEST_DIR/codex_prompt.txt" ]; then
  echo "FAIL: codex should not run when -c selects gemini" >&2
  exit 1
fi

# A nonexistent config file is a clear error.
set +e
err="$(run_cli -c "$TEST_DIR/missing-config" "x" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "missing -c file should exit 2"
assert_contains "$err" "config file not found" "missing -c file should be explained"

echo "PASS: -c selects an alternate config and rejects a missing file"
