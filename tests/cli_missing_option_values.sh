#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

stdout_file="$TEST_DIR/stdout.txt"
stderr_file="$TEST_DIR/stderr.txt"

# --- bare value-taking flags exit 2 with a usage line, nothing on stdout ---
bare_flags=(-m -p -f -c -i --context --model --providers --video --timeout)
for flag in "${bare_flags[@]}"; do
  set +e
  run_cli "$flag" >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  err="$(cat "$stderr_file")"
  assert_eq "2" "$status" "$flag with no value should exit 2"
  assert_eq "" "$(cat "$stdout_file")" "$flag with no value should print nothing on stdout"
  if [ -z "$err" ]; then
    echo "FAIL: $flag with no value should print a nonempty stderr line" >&2
    exit 1
  fi
  assert_contains "$err" "midflight:" "$flag with no value should print a midflight: line"
  assert_contains "$err" "$flag" "$flag with no value should name the flag"
done

echo "PASS: bare value-taking flags exit 2 with a usage line"

# A present invalid value stays on the existing usage path.
set +e
run_cli --timeout abc >"$stdout_file" 2>"$stderr_file"
status=$?
set -e
assert_eq "2" "$status" "--timeout abc should exit 2"
assert_eq "" "$(cat "$stdout_file")" "--timeout abc should print nothing on stdout"
assert_eq "midflight: invalid --timeout 'abc' (non-negative integer seconds expected; 0 disables the bound)" \
  "$(cat "$stderr_file")" \
  "--timeout abc should keep the invalid-value message"

echo "PASS: present invalid --timeout stays a usage error"

# --- a following flag is not a value; --video must not reach the engine ---
write_config <<'EOF'
provider=codex
gemini_model=test-gemini
EOF
write_gemini_stub "should-not-run"

value_flags=(
  -m -p --dual --providers --model -c -f --context -i
  --video --image-gen --video-gen --ref --aspect --timeout
)
for flag in "${value_flags[@]}"; do
  set +e
  run_cli "$flag" --help >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
  err="$(cat "$stderr_file")"
  assert_eq "2" "$status" "$flag --help should exit 2"
  assert_eq "" "$(cat "$stdout_file")" "$flag --help should print nothing on stdout"
  assert_contains "$err" "midflight:" "$flag --help should print a midflight: line"
  assert_contains "$err" "(got '--help')" "$flag --help should reject the flag as a value"
  if [[ "$err" == *"mode=video"* ]]; then
    echo "FAIL: $flag --help should not log mode=video" >&2
    echo "Actual: $err" >&2
    exit 1
  fi
done

if [ -f "$TEST_DIR/gemini_prompt.txt" ]; then
  echo "FAIL: a flag-like option value should not call the provider" >&2
  exit 1
fi

echo "PASS: value-taking flags reject a following flag"

# A real relative path still enters video mode.
printf 'fake-video-bytes\n' > "$TEST_DIR/ad.mp4"
write_gemini_stub "video-ok"
pushd "$TEST_DIR" >/dev/null
set +e
output="$(run_cli --video ./ad.mp4 2>"$stderr_file")"
status=$?
set -e
popd >/dev/null
assert_eq "0" "$status" "--video ./ad.mp4 should enter video mode"
assert_eq "video-ok" "$output" "--video ./ad.mp4 should return the provider response"
assert_contains "$(cat "$stderr_file")" "mode=video" \
  "--video ./ad.mp4 should log mode=video"

echo "PASS: cli_missing_option_values"
