#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

stdout_file="$TEST_DIR/stdout.txt"
stderr_file="$TEST_DIR/stderr.txt"

assert_usage_reject() {
  local label="$1"
  local needle="$2"
  shift 2
  local status=0
  local err=""

  set +e
  run_cli "$@" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  err="$(cat "$stderr_file")"
  assert_eq "2" "$status" "$label should exit 2"
  assert_eq "" "$(cat "$stdout_file")" "$label should print nothing on stdout"
  assert_contains "$err" "midflight:" "$label should print a midflight: line"
  assert_contains "$err" "$needle" "$label should explain the failure"
}

write_codex_effort_probe() {
  cat > "$TEST_DIR/bin/codex" <<'EOF'
#!/bin/bash
set -euo pipefail
effort_arg=""
output_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    -c)
      case "$2" in
        model_reasoning_effort=*) effort_arg="$2" ;;
      esac
      shift 2
      ;;
    -o|--output-last-message) output_file="$2"; shift 2 ;;
    --model|--sandbox) shift 2 ;;
    --skip-git-repo-check) shift ;;
    *) shift ;;
  esac
done
printf '%s' "$effort_arg" > "$TEST_DIR/codex_effort_arg.txt"
printf 'probe-ok\n' > "$output_file"
EOF
  chmod +x "$TEST_DIR/bin/codex"
}

echo "Test 1: -p agy --model M --effort high reaches the agy stub"

write_config <<'EOF'
provider=codex
codex_model=keep-me
agy_model=old-model
agy_effort=low
EOF

write_agy_stub "stub-agy-ok"
run_cli -p agy --model M --effort high "quick take" >/dev/null

assert_eq "M" "$(cat "$TEST_DIR/agy_model.txt")" \
  "--model M should be passed to agy"
assert_eq "high" "$(cat "$TEST_DIR/agy_effort.txt")" \
  "--effort high should be passed to agy"
assert_eq "" "$(cat "$TEST_DIR/agy_unknown_args.txt")" \
  "agy should recognize --model and --effort"
assert_eq "agy_model=old-model" \
  "$(grep '^agy_model=' "$HOME/.config/mid-flight/config")" \
  "--model should not modify the user's real config"
assert_eq "agy_effort=low" \
  "$(grep '^agy_effort=' "$HOME/.config/mid-flight/config")" \
  "--effort should not modify the user's real config"

echo "Test 2: -p antigravity writes agy_effort"

write_agy_stub "stub-agy-ok"
run_cli -p antigravity --effort medium "test question" >/dev/null
assert_eq "medium" "$(cat "$TEST_DIR/agy_effort.txt")" \
  "antigravity should use the agy effort key"

echo "Test 3: --effort without -p follows the configured provider"

write_config <<'EOF'
provider=grok
EOF

write_grok_stub "stub-grok-ok"
run_cli --effort high "test question" >/dev/null
assert_eq "high" "$(cat "$TEST_DIR/grok_effort.txt")" \
  "--effort should set grok_effort for provider=grok"

write_grok_stub "stub-grok-ok"
run_cli -p grok-build --effort medium "test question" >/dev/null
assert_eq "medium" "$(cat "$TEST_DIR/grok_effort.txt")" \
  "grok-build should use the grok effort key"

echo "Test 4: codex effort is codex_reasoning_effort"

write_codex_effort_probe
rm -f "$HOME/.config/mid-flight/config"
run_cli --effort xhigh "test question" >/dev/null
assert_eq 'model_reasoning_effort="xhigh"' "$(cat "$TEST_DIR/codex_effort_arg.txt")" \
  "--effort with no provider should set the default codex effort"

run_cli -p codex --effort low "test question" >/dev/null
assert_eq 'model_reasoning_effort="low"' "$(cat "$TEST_DIR/codex_effort_arg.txt")" \
  "-p codex --effort should override codex_reasoning_effort"

echo "Test 5: a provider with no effort key exits 2"

write_config <<'EOF'
provider=gemini
gemini_model=test-gemini
EOF
config_before="$(cat "$HOME/.config/mid-flight/config")"
write_gemini_stub "should-not-run"
rm -f "$TEST_DIR/gemini_prompt.txt"

assert_usage_reject "gemini --effort" "not supported for provider 'gemini'" \
  --effort high "test question"

if [ -f "$TEST_DIR/gemini_prompt.txt" ]; then
  echo "FAIL: --effort for gemini should not call the provider" >&2
  exit 1
fi
assert_eq "$config_before" "$(cat "$HOME/.config/mid-flight/config")" \
  "a rejected --effort should not modify the user's real config"

for provider in opencode oz claude; do
  assert_usage_reject "$provider --effort" "not supported for provider '$provider'" \
    -p "$provider" --effort high "test question"
done

echo "Test 6: an unknown provider is rejected like --model"

write_config <<'EOF'
provider=bogus
EOF

assert_usage_reject "unknown provider --effort" "unknown provider 'bogus' for --effort mapping" \
  --effort high "test question"

echo "Test 7: --effort cannot be combined with dual-consult"

assert_usage_reject "--effort --dual" "--effort cannot be combined with dual-consult" \
  --dual agy --effort high "x"
assert_usage_reject "--effort --providers" "--effort cannot be combined with dual-consult" \
  --providers codex,agy --effort high "x"

echo "Test 8: video --effort follows the provider that will run"

write_config <<'EOF'
provider=codex
codex_model=test-model
EOF
printf 'fake-video-bytes\n' > "$TEST_DIR/clip.mp4"
write_agy_stub "video-agy-ok"
rm -f "$TEST_DIR/agy_effort.txt"

run_cli --video "$TEST_DIR/clip.mp4" --effort high "describe this" >/dev/null
assert_eq "high" "$(cat "$TEST_DIR/agy_effort.txt")" \
  "video mode should pass --effort to agy when agy is on PATH"

rm -f "$TEST_DIR/bin/agy" "$TEST_DIR/gemini_prompt.txt"
write_gemini_stub "should-not-run"
assert_usage_reject "video gemini --effort" "not supported for provider 'gemini'" \
  --video "$TEST_DIR/clip.mp4" --effort high "describe this"
if [ -f "$TEST_DIR/gemini_prompt.txt" ]; then
  echo "FAIL: video --effort should not call gemini when gemini has no effort key" >&2
  exit 1
fi

echo "Test 9: image-gen and video-gen follow the provider that will run"

write_config <<'EOF'
provider=agy
agy_model=test-agy
EOF
plane="$TEST_DIR/paper-plane.png"
printf 'png\n' > "$plane"
write_grok_stub "$plane"
output="$(run_cli --image-gen "a paper plane over a fjord" --effort high)"
if [ ! -f "$output" ] || [ ! "$output" -ef "$plane" ]; then
  echo "FAIL: image-gen --effort should still print the grok image path" >&2
  echo "Actual: $output" >&2
  exit 1
fi
assert_eq "high" "$(cat "$TEST_DIR/grok_effort.txt")" \
  "image-gen should pass --effort to the grok fallback"

write_config <<'EOF'
provider=codex
codex_model=test-codex
EOF
clip="$TEST_DIR/gen-clip.mp4"
printf 'mp4\n' > "$clip"
write_grok_stub "$clip"
output="$(run_cli --effort low --video-gen "the paper plane banks once")"
if [ ! -f "$output" ] || [ ! "$output" -ef "$clip" ]; then
  echo "FAIL: video-gen --effort should still print the grok video path" >&2
  echo "Actual: $output" >&2
  exit 1
fi
assert_eq "low" "$(cat "$TEST_DIR/grok_effort.txt")" \
  "video-gen should pass --effort to grok"

echo "Test 10: a config with no provider= line does not abort --model or --effort"

write_config <<'EOF'
codex_model=old-model
EOF

cat > "$TEST_DIR/bin/codex" <<'EOF'
#!/bin/bash
set -euo pipefail
model=""
effort_arg=""
output_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    -c)
      case "$2" in
        model_reasoning_effort=*) effort_arg="$2" ;;
      esac
      shift 2
      ;;
    -o|--output-last-message) output_file="$2"; shift 2 ;;
    --sandbox) shift 2 ;;
    --skip-git-repo-check) shift ;;
    *) shift ;;
  esac
done
printf '%s' "$model" > "$TEST_DIR/codex_model.txt"
printf '%s' "$effort_arg" > "$TEST_DIR/codex_effort_arg.txt"
printf 'probe-ok\n' > "$output_file"
EOF
chmod +x "$TEST_DIR/bin/codex"

run_cli --model gpt-5 "test question" >/dev/null
assert_eq "gpt-5" "$(cat "$TEST_DIR/codex_model.txt")" \
  "--model with no provider= line should set the default codex model"

run_cli --effort low "test question" >/dev/null
assert_eq 'model_reasoning_effort="low"' "$(cat "$TEST_DIR/codex_effort_arg.txt")" \
  "--effort with no provider= line should set the default codex effort"

echo "PASS: --effort maps to the active provider's effort key"
