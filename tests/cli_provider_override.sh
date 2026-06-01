#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

# Config selects codex, but -p overrides to gemini for this one call.
write_config <<'EOF'
provider=codex
codex_model=test-model
gemini_model=test-gemini
EOF

write_codex_stub "should-not-run"
write_gemini_stub "gemini-ok"

output="$(run_cli -p gemini "Which provider answered?")"

assert_eq "gemini-ok" "$output" "-p should route to the overridden provider"

if [ -f "$TEST_DIR/codex_prompt.txt" ]; then
  echo "FAIL: codex should not have been invoked when -p gemini is set" >&2
  exit 1
fi

prompt="$(cat "$TEST_DIR/gemini_prompt.txt")"
assert_contains "$prompt" "Which provider answered?" "gemini should receive the question"

echo "PASS: -p overrides the configured provider without touching the real config"
