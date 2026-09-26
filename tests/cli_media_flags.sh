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

output="$(run_cli --video-gen "the plane banks once" --aspect 9:16 --ref "$ref" --ref "$second")"
if [ ! -f "$output" ] || [ ! "$output" -ef "$clip" ]; then
  echo "FAIL: --video-gen with refs should print the saved video" >&2
  echo "Actual: $output" >&2
  exit 1
fi
grok_prompt="$(cat "$TEST_DIR/grok_prompt.txt")"
assert_contains "$grok_prompt" "Aspect ratio: 9:16" "the video prompt should name the aspect ratio"
assert_contains "$grok_prompt" "opening frame:" "the first reference should be the opening frame"
assert_contains "$grok_prompt" "sky.png" "the second reference should be included"

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
