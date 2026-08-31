#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
EOF

write_agy_stub "video-agy-ok"

VIDEO_FILE="$TEST_DIR/sample.mp4"
printf 'video-bytes' > "$VIDEO_FILE"

output="$(run_query "$VIDEO_FILE" video "Focus on pacing and overlays.")"
add_dir="$(cat "$TEST_DIR/agy_add_dir.txt")"
captured_prompt="$(cat "$TEST_DIR/agy_prompt.txt")"

assert_eq "video-agy-ok" "$output" "video mode should return stubbed agy output when agy is on PATH"
assert_contains "$captured_prompt" "Focus on pacing and overlays." \
  "video mode should pass the custom video prompt"
assert_contains "$captured_prompt" "${add_dir}/video_input.mp4" \
  "video mode should name the staged file by path"
if [[ "$captured_prompt" == *"@"* ]]; then
  echo "FAIL: agy video prompts must not use Gemini @path syntax" >&2
  exit 1
fi
assert_eq "no" "$(cat "$TEST_DIR/agy_skip_permissions.txt")" \
  "video must not skip agy permissions"

if [ -x "$TEST_DIR/bin/gemini" ]; then
  echo "FAIL: this test must not install a gemini stub" >&2
  exit 1
fi

echo "PASS: video mode prefers agy, stages via --add-dir, and skips @path"
