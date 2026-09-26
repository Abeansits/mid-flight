#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

# A Codex config falls back to Grok. Codex must not be called.
write_config <<'EOF'
provider=codex
codex_model=test-codex
EOF

clip="$TEST_DIR/clip.mp4"
printf 'mp4\n' > "$clip"
write_grok_stub "$clip"
write_codex_stub "should-not-run"

output="$(run_cli --video-gen "the paper plane banks once" --aspect 16:9)"
if [ ! -f "$output" ] || [ ! "$output" -ef "$clip" ]; then
  echo "FAIL: --video-gen should print the grok video path" >&2
  echo "Expected file: $clip" >&2
  echo "Actual:        $output" >&2
  exit 1
fi
assert_eq "yes" "$(cat "$TEST_DIR/grok_always_approve.txt")" \
  "video-gen grok must pass --always-approve"
assert_eq "" "$(cat "$TEST_DIR/grok_sandbox.txt")" \
  "video-gen grok must not pass --sandbox read-only"
grok_prompt="$(cat "$TEST_DIR/grok_prompt.txt")"
assert_contains "$grok_prompt" "image_gen" \
  "a video with no reference should start by generating a still"
assert_contains "$grok_prompt" "Set this ratio on the source still with image_gen" \
  "a video with no reference should set the aspect on the still"
assert_contains "$grok_prompt" "image_to_video" "the grok prompt should name image_to_video"
assert_contains "$grok_prompt" "the paper plane banks once" \
  "the grok prompt should include the video description"
if [ -f "$TEST_DIR/codex_prompt.txt" ]; then
  echo "FAIL: video-gen must not call codex" >&2
  exit 1
fi

# -p grok-build is Grok. A sentence around a temp-home path still resolves.
mkdir -p "$HOME/.grok/videos"
cat > "$TEST_DIR/bin/grok" <<'EOF'
#!/bin/bash
set -euo pipefail
target="$HOME/.grok/videos/plane.mp4"
mkdir -p "$(dirname "$target")"
printf 'plane\n' > "$target"
printf 'Done. The file is %s.\n' "$target"
EOF
chmod +x "$TEST_DIR/bin/grok"

output="$(run_cli -p grok-build --video-gen "a paper plane banks once")"
lasting="$HOME/.grok/videos/plane.mp4"
if [ ! -f "$output" ] || [ ! "$output" -ef "$lasting" ]; then
  echo "FAIL: --video-gen should print the path that survives the temp HOME" >&2
  echo "Expected file: $lasting" >&2
  echo "Actual:        $output" >&2
  exit 1
fi
assert_eq "plane" "$(cat "$output")" "the printed path should be the saved video"
if [[ "$output" == *midflight-cli* ]] || [[ "$output" == *"Done."* ]]; then
  echo "FAIL: stdout should be only the resolved path" >&2
  echo "Actual: $output" >&2
  exit 1
fi

# Usage errors.
set +e
err="$(run_cli -p codex --video-gen "a cat walking" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "-p codex --video-gen should exit 2"
assert_contains "$err" "supports grok" "-p codex should name the supported provider"

set +e
err="$(run_cli --video-gen 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "--video-gen without a prompt should exit 2"
assert_contains "$err" "requires a prompt" "a missing prompt should be explained"

printf 'fake\n' > "$TEST_DIR/ad.mp4"
set +e
err="$(run_cli --video-gen "a cat walking" --video "$TEST_DIR/ad.mp4" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "--video-gen plus --video should exit 2"
assert_contains "$err" "cannot be combined with --video" "--video-gen plus --video should be explained"

set +e
err="$(run_cli --video-gen "a cat" --image-gen "a dog" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "--video-gen plus --image-gen should exit 2"
assert_contains "$err" "cannot be combined with --image-gen" \
  "--video-gen plus --image-gen should be explained"

set +e
err="$(run_cli --dual agy --video-gen "a cat walking" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "--video-gen plus --dual should exit 2"
assert_contains "$err" "consult-only" "--video-gen plus --dual should stay consult-only"

write_grok_stub "no video was saved"
set +e
err="$(run_cli -p grok --video-gen "a missing file" 2>&1)"
status=$?
set -e
assert_eq "1" "$status" "video-gen with no saved file should exit 1"
assert_contains "$err" "did not produce a saved video file" \
  "a missing video should be explained"

# Mentioning the reference image is not a saved video.
ref="$TEST_DIR/plane.png"
printf 'png\n' > "$ref"
write_grok_stub "See $ref"
set +e
err="$(run_cli -p grok --video-gen "a paper plane banks" --ref "$ref" 2>&1)"
status=$?
set -e
assert_eq "1" "$status" "naming the reference image should not count as a video"
assert_contains "$err" "did not produce a saved video file" \
  "a reference-only reply should be explained"

# When both paths appear, keep the video.
saved="$TEST_DIR/bank.mp4"
printf 'mp4\n' > "$saved"
write_grok_stub "Opened $ref then saved $saved"
output="$(run_cli -p grok --video-gen "a paper plane banks" --ref "$ref")"
if [ ! -f "$output" ] || [ ! "$output" -ef "$saved" ]; then
  echo "FAIL: --video-gen should print the saved video, not the reference" >&2
  echo "Actual: $output" >&2
  exit 1
fi

echo "PASS: --video-gen routes to grok and rejects the other modes"
