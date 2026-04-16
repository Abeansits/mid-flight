#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=opencode
opencode_model=anthropic/claude-sonnet-4-0
opencode_variant=max
opencode_format=default
EOF

cat > "$TEST_DIR/bin/opencode" <<EOF
#!/bin/bash

set -euo pipefail

model=""
variant=""
format=""
dir=""
prompt=""

while [ \$# -gt 0 ]; do
  case "\$1" in
    run)
      shift
      ;;
    -m|--model)
      model="\$2"
      shift 2
      ;;
    --variant)
      variant="\$2"
      shift 2
      ;;
    --format)
      format="\$2"
      shift 2
      ;;
    --dir)
      dir="\$2"
      shift 2
      ;;
    *)
      prompt="\$1"
      shift
      ;;
  esac
done

printf '%s' "\$model" > "$TEST_DIR/opencode_model.txt"
printf '%s' "\$variant" > "$TEST_DIR/opencode_variant.txt"
printf '%s' "\$format" > "$TEST_DIR/opencode_format.txt"
printf '%s' "\$dir" > "$TEST_DIR/opencode_dir.txt"
printf '%s' "\$prompt" > "$TEST_DIR/opencode_prompt.txt"
printf 'opencode-ok\n'
EOF

chmod +x "$TEST_DIR/bin/opencode"

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
We are testing OpenCode integration.

## Question
Should MidFlight share one provider contract?
EOF
)"

output="$(run_query "$QUERY_FILE" consult)"

assert_eq "opencode-ok" "$output" "consult query should return stubbed OpenCode output"
assert_eq "anthropic/claude-sonnet-4-0" "$(cat "$TEST_DIR/opencode_model.txt")" "OpenCode should receive the configured model"
assert_eq "max" "$(cat "$TEST_DIR/opencode_variant.txt")" "OpenCode should receive the configured variant"
assert_eq "default" "$(cat "$TEST_DIR/opencode_format.txt")" "OpenCode should receive the configured format"
assert_eq "$ROOT_DIR" "$(cat "$TEST_DIR/opencode_dir.txt")" "OpenCode should receive the current working directory"
assert_contains "$(cat "$TEST_DIR/opencode_prompt.txt")" \
  "You are a senior engineer being consulted mid-development." \
  "OpenCode prompt should include the consult system prompt"
assert_contains "$(cat "$TEST_DIR/opencode_prompt.txt")" \
  "Should MidFlight share one provider contract?" \
  "OpenCode prompt should include the query body"

echo "PASS: consult mode routes through opencode with the expected flags and prompt"
