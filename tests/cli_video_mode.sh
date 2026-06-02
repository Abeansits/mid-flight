#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

# Configured provider is codex, but --video must force gemini.
write_config <<'EOF'
provider=codex
gemini_model=test-gemini
EOF

write_gemini_stub "video-ok"

printf 'fake-video-bytes\n' > "$TEST_DIR/clip.mp4"

output="$(run_cli --video "$TEST_DIR/clip.mp4" "Does this match the storyboard?")"

assert_eq "video-ok" "$output" "--video should route through gemini"

prompt="$(cat "$TEST_DIR/gemini_prompt.txt")"
assert_contains "$prompt" "Does this match the storyboard?" \
  "the video prompt should include the inline question"
assert_contains "$prompt" "@" "the video prompt should reference the staged file with @"

# --video plus --context is a usage error.
set +e
err="$(run_cli --video "$TEST_DIR/clip.mp4" --context "$TEST_DIR/clip.mp4" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "--video plus --context should exit 2"
assert_contains "$err" "do not apply to video mode" "--video plus --context should be explained"

echo "PASS: --video forces gemini, includes the prompt, and rejects --context"
