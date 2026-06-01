#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
codex_model=test-model
EOF

write_codex_stub "inline-ok"

output="$(run_cli "Should we use SSE or WebSockets?")"

assert_eq "inline-ok" "$output" "inline question should return the stubbed codex response"

prompt="$(cat "$TEST_DIR/codex_prompt.txt")"
assert_contains "$prompt" "You are a senior engineer being consulted mid-development." \
  "inline question should use the consult system prompt"
assert_contains "$prompt" "## Question" "inline question should assemble a Question section"
assert_contains "$prompt" "Should we use SSE or WebSockets?" \
  "inline question should include the question text"

echo "PASS: inline question assembles a query file and routes through the provider"
