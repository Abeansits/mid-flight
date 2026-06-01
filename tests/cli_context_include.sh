#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
codex_model=test-model
EOF

write_codex_stub "context-ok"

printf 'We are migrating the auth service to OAuth.\n' > "$TEST_DIR/context.md"
mkdir -p "$TEST_DIR/src"
printf 'export const TOKEN_TTL = 3600;\n' > "$TEST_DIR/src/auth.ts"

output="$(run_cli --context "$TEST_DIR/context.md" \
  --include "$TEST_DIR/src/*.ts" \
  "Is the token TTL reasonable?")"

assert_eq "context-ok" "$output" "context+include run should return the stubbed response"

prompt="$(cat "$TEST_DIR/codex_prompt.txt")"
assert_contains "$prompt" "## Context" "should assemble a Context section"
assert_contains "$prompt" "migrating the auth service to OAuth" \
  "Context should include the --context file contents"
assert_contains "$prompt" "TOKEN_TTL = 3600" \
  "Context should include the --include file contents"
assert_contains "$prompt" "src/auth.ts" "Context should label the included file"
assert_contains "$prompt" "Is the token TTL reasonable?" "should include the question"

echo "PASS: --context and --include fold into the Context section"
