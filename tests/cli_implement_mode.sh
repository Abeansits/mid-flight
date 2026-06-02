#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
codex_model=test-model
EOF

write_codex_stub "implement-ok"

output="$(run_cli -m implement "Add a retry wrapper to fetchUser()")"

assert_eq "implement-ok" "$output" "implement mode should return the stubbed response"

prompt="$(cat "$TEST_DIR/codex_prompt.txt")"
assert_contains "$prompt" "implementation" "implement mode should use the implement system prompt"
assert_contains "$prompt" "Add a retry wrapper to fetchUser()" "should include the instruction"

echo "PASS: -m implement routes through the implement system prompt"
