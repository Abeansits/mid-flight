#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
codex_model=test-codex
EOF

ref="$TEST_DIR/plane.png"
printf 'ref\n' > "$ref"
out="$TEST_DIR/out.png"
printf 'png\n' > "$out"
write_codex_stub "$out"

output="$(run_cli --image-gen "a paper plane over a fjord" --aspect 16:9 --ref "$ref")"
if [ ! -f "$output" ] || [ ! "$output" -ef "$out" ]; then
  echo "FAIL: --image-gen with --ref should still print the saved image" >&2
  echo "Actual: $output" >&2
  exit 1
fi
prompt="$(cat "$TEST_DIR/codex_prompt.txt")"
assert_contains "$prompt" "Aspect ratio: 16:9" "the prompt should name the aspect ratio"
assert_contains "$prompt" "Codex size: 1536x864" "16:9 should map to the Codex pixel size"
assert_contains "$prompt" "plane.png" "the prompt should name the reference file"
attached="$(cat "$TEST_DIR/codex_images.txt")"
if [ ! -f "$attached" ] || [ ! "$attached" -ef "$ref" ]; then
  echo "FAIL: Codex should receive the reference via -i" >&2
  echo "Actual: $attached" >&2
  exit 1
fi

# Video: first ref is the opening frame. A Codex config still uses Grok.
second="$TEST_DIR/sky.png"
printf 'sky\n' > "$second"
clip="$TEST_DIR/clip.mp4"
printf 'mp4\n' > "$clip"
write_grok_stub "$clip"

set +e
output="$(run_cli --video-gen "the plane banks once" --aspect 9:16 --ref "$ref" --ref "$second" 2>"$TEST_DIR/video_err.txt")"
status=$?
set -e
if [ "$status" -ne 0 ]; then
  echo "FAIL: --video-gen with refs should exit 0" >&2
  echo "Status: $status" >&2
  echo "Stdout: $output" >&2
  cat "$TEST_DIR/video_err.txt" >&2
  exit 1
fi
if [ ! -f "$output" ] || [ ! "$output" -ef "$clip" ]; then
  echo "FAIL: --video-gen with refs should print the saved video" >&2
  echo "Actual: $output" >&2
  exit 1
fi
if [[ "$output" == *"could not read"* ]] || [[ "$output" == *"midflight:"* ]]; then
  echo "FAIL: reference diagnostics should stay off stdout" >&2
  echo "Actual: $output" >&2
  exit 1
fi
grok_prompt="$(cat "$TEST_DIR/grok_prompt.txt")"
assert_contains "$grok_prompt" "Aspect ratio: 9:16" "the video prompt should name the aspect ratio"
assert_contains "$grok_prompt" "Do not pass aspect_ratio to image_to_video" \
  "a reference clip should not send the ratio to image_to_video"
assert_contains "$grok_prompt" "opening frame:" "the first reference should be the opening frame"
assert_contains "$grok_prompt" "Later reference images guide the clip" \
  "later references should be guidance"
assert_contains "$grok_prompt" "They do not replace the opening frame" \
  "later references should not replace the opening frame"
assert_contains "$grok_prompt" "sky.png" "the second reference should be included"
frame_at="$(awk -v needle="opening frame: " 'index($0, needle) { print NR; exit }' <<<"$grok_prompt")"
guide_at="$(awk -v needle="- $second" 'index($0, needle) { print NR; exit }' <<<"$grok_prompt")"
if [ -z "$frame_at" ] || [ -z "$guide_at" ] || [ "$frame_at" -ge "$guide_at" ]; then
  echo "FAIL: the opening frame should be listed before later references" >&2
  echo "opening frame line: ${frame_at:-missing}" >&2
  echo "later reference line: ${guide_at:-missing}" >&2
  exit 1
fi
video_err="$(cat "$TEST_DIR/video_err.txt")"
assert_contains "$video_err" "could not read the size" \
  "a text reference should say the opening frame size was not read"

# Usage errors.
set +e
err="$(run_cli --image-gen "a cat" --aspect 4:3 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "an unsupported aspect should exit 2"
assert_contains "$err" "must be 1:1, 16:9, 9:16, 3:2, or 2:3" "a bad aspect should list the ratios"

set +e
err="$(run_cli --image-gen "a cat" --ref "$TEST_DIR/missing.png" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "a missing reference should exit 2"
assert_contains "$err" "reference file not found" "a missing reference should be explained"

set +e
err="$(run_cli --aspect 1:1 "just a question" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "--aspect without generation should exit 2"
assert_contains "$err" "apply only to --image-gen and --video-gen" \
  "--aspect on a consult should be explained"

echo "PASS: --ref and --aspect reach image and video generation"
