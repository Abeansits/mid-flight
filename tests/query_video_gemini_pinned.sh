#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

# Explicit gemini must win even when agy is also on PATH.
write_config <<'EOF'
provider=gemini
gemini_model=test-gemini
EOF

write_agy_stub "should-not-run"
write_gemini_stub "video-gemini-pinned"

VIDEO_FILE="$TEST_DIR/sample.mp4"
printf 'video-bytes' > "$VIDEO_FILE"

output="$(run_query "$VIDEO_FILE" video "Pinned to Gemini.")"

assert_eq "video-gemini-pinned" "$output" \
  "provider=gemini should keep video on Gemini even if agy is installed"

if [ -f "$TEST_DIR/agy_prompt.txt" ]; then
  echo "FAIL: pinned gemini video must not invoke agy" >&2
  exit 1
fi

assert_contains "$(cat "$TEST_DIR/gemini_prompt.txt")" "@" \
  "pinned Gemini video should still use @path"

echo "PASS: provider=gemini pins video to Gemini when both CLIs exist"
