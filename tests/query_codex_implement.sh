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
printf 'implement-ok\n' > "\$output_file"
EOF

chmod +x "$TEST_DIR/bin/codex"

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
Implement-mode sandbox check.

## Question
Add a retry wrapper to fetchUser().
EOF
)"

output="$(run_query "$QUERY_FILE" implement)"

assert_eq "implement-ok" "$output" "implement query should return stubbed codex output"
assert_contains "$(cat "$TEST_DIR/codex_prompt.txt")" \
  "implementation" \
  "implement prompt should include the implement system prompt"
assert_contains "$(cat "$TEST_DIR/codex_prompt.txt")" \
  "Add a retry wrapper to fetchUser()" \
  "implement prompt should include the query body"

CODEX_ARGS="$(cat "$TEST_DIR/codex_args.txt")"

# One arg per line, so adjacent lines assert `--sandbox workspace-write` as a pair:
# read-only, or the value merely appearing elsewhere in argv, must fail.
assert_contains "$CODEX_ARGS" $'--sandbox\nworkspace-write' \
  "implement codex sandbox mode should be workspace-write"

if [[ "$CODEX_ARGS" == *"--full-auto"* ]]; then
  echo "FAIL: codex invocation must not pass --full-auto (removed in codex-cli 0.147.0)" >&2
  exit 1
fi

echo "PASS: implement mode routes through codex with workspace-write sandbox"
