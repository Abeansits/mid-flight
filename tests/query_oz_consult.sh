#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=oz
oz_model=auto-genius
oz_output_format=text
oz_profile=pairing
EOF

cat > "$TEST_DIR/bin/oz" <<EOF
#!/bin/bash

set -euo pipefail

model=""
output_format=""
profile=""
cwd=""
prompt=""

while [ \$# -gt 0 ]; do
  case "\$1" in
    agent|run)
      shift
      ;;
    --prompt|-p)
      prompt="\$2"
      shift 2
      ;;
    --model)
      model="\$2"
      shift 2
      ;;
    --output-format)
      output_format="\$2"
      shift 2
      ;;
    --profile)
      profile="\$2"
      shift 2
      ;;
    -C|--cwd)
      cwd="\$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

printf '%s' "\$model" > "$TEST_DIR/oz_model.txt"
printf '%s' "\$output_format" > "$TEST_DIR/oz_output_format.txt"
printf '%s' "\$profile" > "$TEST_DIR/oz_profile.txt"
printf '%s' "\$cwd" > "$TEST_DIR/oz_cwd.txt"
printf '%s' "\$prompt" > "$TEST_DIR/oz_prompt.txt"
printf 'oz-ok\n'
EOF

chmod +x "$TEST_DIR/bin/oz"

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
We are testing Oz integration.

## Question
Should MidFlight support more agent CLIs?
EOF
)"

output="$(run_query "$QUERY_FILE" consult)"

assert_eq "oz-ok" "$output" "consult query should return stubbed Oz output"
assert_eq "auto-genius" "$(cat "$TEST_DIR/oz_model.txt")" "Oz should receive the configured model"
assert_eq "text" "$(cat "$TEST_DIR/oz_output_format.txt")" "Oz should receive the configured output format"
assert_eq "pairing" "$(cat "$TEST_DIR/oz_profile.txt")" "Oz should receive the configured profile"
assert_eq "$ROOT_DIR" "$(cat "$TEST_DIR/oz_cwd.txt")" "Oz should receive the current working directory"
assert_contains "$(cat "$TEST_DIR/oz_prompt.txt")" \
  "You are a senior engineer being consulted mid-development." \
  "Oz prompt should include the consult system prompt"
assert_contains "$(cat "$TEST_DIR/oz_prompt.txt")" \
  "Should MidFlight support more agent CLIs?" \
  "Oz prompt should include the query body"

echo "PASS: consult mode routes through oz with the expected flags and prompt"
