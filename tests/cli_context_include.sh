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

# Additional coverage for the set -u / assembly paths that were previously untested
# (bare-inline, --context-only, --include-only). These exercise build_query_file
# branches that hit the files array (or skip it) and would have crashed before the fix.
write_codex_stub "bare-inline-ok"
output="$(run_cli "Bare inline only, no context flags at all?")"
assert_eq "bare-inline-ok" "$output" "bare inline should still work"
prompt="$(cat "$TEST_DIR/codex_prompt.txt")"
assert_contains "$prompt" "## Question" "bare inline must have Question section"
# Critical: must NOT have a Context section at all
if grep -q '^## Context' "$TEST_DIR/codex_prompt.txt"; then
  echo "FAIL: bare inline must not emit a Context section" >&2
  exit 1
fi

# --context only (no -i): must emit Context block with the provided text, but ZERO
# file ### subsections (the files array is empty; the robust + idiom + guards prevent
# bogus empty ### blocks and the old unbound crash).
write_codex_stub "context-only-ok"
printf 'Only context, no includes.\nSecond line.\n' > "$TEST_DIR/ctx_only.md"
output="$(run_cli --context "$TEST_DIR/ctx_only.md" "Context-only question?")"
assert_eq "context-only-ok" "$output" "context-only should return stub"
prompt="$(cat "$TEST_DIR/codex_prompt.txt")"
assert_contains "$prompt" "## Context" "context-only must emit Context"
assert_contains "$prompt" "Only context, no includes." "context-only must include the file text"
assert_contains "$prompt" "Context-only question?" "context-only must include Q"
# No file blocks
if grep -q '^### ' "$TEST_DIR/codex_prompt.txt"; then
  echo "FAIL: context-only must not emit any ### file blocks" >&2
  exit 1
fi

# --include only (no --context): still emits ## Context (for the subsections), plus the
# included files, no top-level context prose.
write_codex_stub "include-only-ok"
mkdir -p "$TEST_DIR/inc"
printf 'include only content here\n' > "$TEST_DIR/inc/foo.txt"
output="$(run_cli --include "$TEST_DIR/inc/*.txt" "Include-only question?")"
assert_eq "include-only-ok" "$output" "include-only should return stub"
prompt="$(cat "$TEST_DIR/codex_prompt.txt")"
assert_contains "$prompt" "## Context" "include-only must still have Context (for subsections)"
assert_contains "$prompt" "inc/foo.txt" "include-only must label the file"
assert_contains "$prompt" "include only content here" "include-only must embed content"
assert_contains "$prompt" "Include-only question?" "include-only Q"

echo "PASS: bare-inline + --context-only + --include-only all assemble cleanly (no unbound, no bogus blocks)"
