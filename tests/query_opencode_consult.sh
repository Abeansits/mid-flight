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

if [ "\${1:-}" = "--version" ]; then
  printf '%s\n' "\${OPENCODE_TEST_VERSION:-1.2.0}"
  exit "\${OPENCODE_TEST_VERSION_STATUS:-0}"
fi

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
      [ "\${OPENCODE_TEST_V2:-0}" != "1" ] || exit 2
      variant="\$2"
      shift 2
      ;;
    --format)
      format="\$2"
      shift 2
      ;;
    --dir)
      [ "\${OPENCODE_TEST_V2:-0}" != "1" ] || exit 2
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
printf '%s' "\$PWD" > "$TEST_DIR/opencode_cwd.txt"
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

# Exercise the actual v2 version banner as well as bare/prefixed semver and
# future major versions. The stub rejects flags removed in v2.
export OPENCODE_TEST_V2=1
for version in 'opencode v2.0.15' '2.0.15' 'v2.0.15' 'opencode v3.0.0-beta.1' '10.0.0'; do
  export OPENCODE_TEST_VERSION="$version"
  output="$(run_query "$QUERY_FILE" consult)"
  assert_eq "opencode-ok" "$output" "OpenCode $version should succeed"
  assert_eq "anthropic/claude-sonnet-4-0#max" "$(cat "$TEST_DIR/opencode_model.txt")" "v2 should encode the variant in the model"
  assert_eq "" "$(cat "$TEST_DIR/opencode_variant.txt")" "v2 should omit --variant"
  assert_eq "" "$(cat "$TEST_DIR/opencode_dir.txt")" "v2 should omit --dir"
  assert_eq "$PWD" "$(cat "$TEST_DIR/opencode_cwd.txt")" "v2 should inherit the working directory"
  assert_eq "default" "$(cat "$TEST_DIR/opencode_format.txt")" "v2 should preserve the format"
  assert_contains "$(cat "$TEST_DIR/opencode_prompt.txt")" "Should MidFlight share one provider contract?" "v2 should preserve the prompt"
done

write_config <<'EOF'
provider=opencode
opencode_model=
opencode_variant=max
opencode_format=json
EOF
stderr="$(run_query "$QUERY_FILE" consult 2>&1 > /dev/null)"
assert_eq "" "$(cat "$TEST_DIR/opencode_model.txt")" "v2 should leave the CLI default model intact"
assert_contains "$stderr" "opencode_variant=max is ignored without opencode_model" "v2 should warn when a variant cannot be applied"
assert_eq "json" "$(cat "$TEST_DIR/opencode_format.txt")" "v2 should preserve JSON format"

write_config <<'EOF'
provider=opencode
opencode_model=
opencode_variant=high
opencode_format=default
EOF
stderr="$(run_query "$QUERY_FILE" consult 2>&1 >/dev/null)"
assert_eq "" "$(cat "$TEST_DIR/opencode_model.txt")" "v2 should leave the CLI default model intact for the built-in variant"
if printf '%s\n' "$stderr" | grep -q "ignored without opencode_model"; then
  echo "FAIL: built-in variant high should not warn when no model is set" >&2
  printf '%s\n' "$stderr" >&2
  exit 1
fi

write_config <<'EOF'
provider=opencode
opencode_model=anthropic/claude-sonnet-4-0
opencode_variant=
EOF
run_query "$QUERY_FILE" consult > /dev/null
assert_eq "anthropic/claude-sonnet-4-0#high" "$(cat "$TEST_DIR/opencode_model.txt")" "v2 should encode the default configured variant"

# The config loader treats blank variants as the default. Exercise an actually
# empty variant directly at the provider boundary. Pin the version in this
# shell; the subshell only isolates the sourced provider functions.
OPENCODE_TEST_VERSION='opencode v2.0.15'
OPENCODE_TEST_VERSION_STATUS=0
(
  source "$ROOT_DIR/scripts/lib/providers.sh"
  RUN_DIR="$TEST_DIR"
  opencode_model='anthropic/claude-sonnet-4-0'
  opencode_variant=''
  opencode_format='default'
  query_opencode 'test prompt' "$TEST_DIR/direct-output.txt"
)
assert_eq "anthropic/claude-sonnet-4-0" "$(cat "$TEST_DIR/opencode_model.txt")" "v2 should not append an empty variant"

write_config <<'EOF'
provider=opencode
opencode_model=anthropic/claude-sonnet-4-0#minimal
opencode_variant=max
EOF
run_query "$QUERY_FILE" consult > /dev/null
assert_eq "anthropic/claude-sonnet-4-0#minimal" "$(cat "$TEST_DIR/opencode_model.txt")" "v2 should preserve an explicit model variant"

export OPENCODE_TEST_V2=0
for version in 'opencode v1.2.0' 'unknown'; do
  export OPENCODE_TEST_VERSION="$version"
  run_query "$QUERY_FILE" consult > /dev/null
  assert_eq "$PWD" "$(cat "$TEST_DIR/opencode_dir.txt")" "v1 or unrecognized versions should retain --dir"
  assert_eq "max" "$(cat "$TEST_DIR/opencode_variant.txt")" "v1 or unrecognized versions should retain --variant"
done

export OPENCODE_TEST_VERSION='opencode v2.0.15'
export OPENCODE_TEST_VERSION_STATUS=1
run_query "$QUERY_FILE" consult > /dev/null
assert_eq "$PWD" "$(cat "$TEST_DIR/opencode_dir.txt")" "a failed version probe should preserve v1 behavior"
assert_eq "max" "$(cat "$TEST_DIR/opencode_variant.txt")" "a failed version probe should preserve --variant"

echo "PASS: OpenCode v2 model variants, default models, and version fallbacks"
