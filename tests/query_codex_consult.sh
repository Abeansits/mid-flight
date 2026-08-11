#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
codex_model=test-model
codex_reasoning_effort=high
EOF

cat > "$TEST_DIR/bin/codex" <<EOF
#!/bin/bash

set -euo pipefail

output_file=""
prompt=""

printf '%s\n' "\$@" > "$TEST_DIR/codex_args.txt"

while [ \$# -gt 0 ]; do
  case "\$1" in
    -o|--output-last-message)
      output_file="\$2"
      shift 2
      ;;
    --model|-c|--sandbox)
      shift 2
      ;;
    --skip-git-repo-check)
      shift
      ;;
    *)
      prompt="\$1"
      shift
      ;;
  esac
done

printf '%s' "\$prompt" > "$TEST_DIR/codex_prompt.txt"
printf 'consult-ok\n' > "\$output_file"
EOF

chmod +x "$TEST_DIR/bin/codex"

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
We are refactoring MidFlight.

## Question
Should we extract prompt files?
EOF
)"

output="$(run_query "$QUERY_FILE" consult)"

assert_eq "consult-ok" "$output" "consult query should return stubbed codex output"
assert_contains "$(cat "$TEST_DIR/codex_prompt.txt")" \
  "You are a senior engineer being consulted mid-development." \
  "consult prompt should include the consult system prompt"
assert_contains "$(cat "$TEST_DIR/codex_prompt.txt")" \
  "Should we extract prompt files?" \
  "consult prompt should include the query body"

# `codex exec` sandboxes to read-only by default, and dropped --full-auto in
# codex-cli 0.147.0; both regressions look like a working call that cannot write.
CODEX_ARGS="$(cat "$TEST_DIR/codex_args.txt")"

assert_contains "$CODEX_ARGS" "--sandbox" \
  "codex invocation should request an explicit sandbox mode"
assert_contains "$CODEX_ARGS" "workspace-write" \
  "codex sandbox mode should be workspace-write"

if [[ "$CODEX_ARGS" == *"--full-auto"* ]]; then
  echo "FAIL: codex invocation must not pass --full-auto (removed in codex-cli 0.147.0)" >&2
  exit 1
fi

echo "PASS: consult mode routes through codex with the expected prompt and sandbox flags"
