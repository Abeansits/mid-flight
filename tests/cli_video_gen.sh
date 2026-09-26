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
grok_prompt="$(cat "$TEST_DIR/grok_prompt.txt")"
assert_contains "$grok_prompt" "image_gen" \
  "a video with no reference should start by generating a still"
assert_contains "$grok_prompt" "Set this ratio on the source still with image_gen" \
  "a video with no reference should set the aspect on the still"
assert_contains "$grok_prompt" "image_to_video" "the grok prompt should name image_to_video"
assert_contains "$grok_prompt" "720p" \
  "a video with no reference should request 720p"
assert_contains "$grok_prompt" "resolution_name" \
  "the 720p request should use resolution_name when that field is listed"
assert_contains "$grok_prompt" "Do not describe the file as HD" \
  "a smaller or unsupported result should not be called HD"
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

# A 16:9 opening frame plus --aspect 9:16 is a conflict. Stop before Grok.
wide="$TEST_DIR/wide.png"
tall="$TEST_DIR/tall.png"
reported="$TEST_DIR/reported.png"
python3 - "$wide" "$tall" "$reported" <<'PY'
import struct, sys, zlib

def write_png(path, width, height):
    raw = b"".join(b"\x00" + (b"\x00" * (width * 3)) for _ in range(height))
    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    blob = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(blob)

write_png(sys.argv[1], 16, 9)
write_png(sys.argv[2], 9, 16)
write_png(sys.argv[3], 400, 736)
PY

rm -f "$TEST_DIR/grok_prompt.txt"
write_grok_stub "$clip"
set +e
err="$(run_cli -p grok --video-gen "a paper plane banks" --aspect 9:16 --ref "$wide" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "a 16:9 opening frame with --aspect 9:16 should exit 2"
assert_contains "$err" "opening frame is 16x9" "the conflict should name the opening frame size"
assert_contains "$err" "--aspect is 9:16" "the conflict should name the requested ratio"
assert_contains "$err" "first --ref" "the conflict should say the first reference sets the shape"
if [ -f "$TEST_DIR/grok_prompt.txt" ]; then
  echo "FAIL: a conflicting --aspect should not call grok" >&2
  exit 1
fi

output="$(run_cli -p grok --video-gen "a paper plane banks" --aspect 16:9 --ref "$wide" 2>"$TEST_DIR/match_err.txt")"
if [ ! -f "$output" ] || [ ! "$output" -ef "$clip" ]; then
  echo "FAIL: a matching opening frame should still print the saved video" >&2
  echo "Actual: $output" >&2
  exit 1
fi
if [[ "$output" == *"midflight:"* ]]; then
  echo "FAIL: a matching opening frame should keep diagnostics off stdout" >&2
  echo "Actual: $output" >&2
  exit 1
fi
match_err="$(cat "$TEST_DIR/match_err.txt")"
if [[ "$match_err" == *"but --aspect"* ]]; then
  echo "FAIL: a matching opening frame should not warn about --aspect" >&2
  echo "Actual: $match_err" >&2
  exit 1
fi

output="$(run_cli -p grok --video-gen "a paper plane banks" --aspect 9:16 --ref "$tall" 2>"$TEST_DIR/tall_err.txt")"
if [ ! -f "$output" ] || [ ! "$output" -ef "$clip" ]; then
  echo "FAIL: a 9:16 opening frame with --aspect 9:16 should print the saved video" >&2
  echo "Actual: $output" >&2
  exit 1
fi
tall_err="$(cat "$TEST_DIR/tall_err.txt")"
if [[ "$tall_err" == *"but --aspect"* ]]; then
  echo "FAIL: a matching portrait frame should not warn about --aspect" >&2
  exit 1
fi

output="$(run_cli -p grok --video-gen "a paper plane banks" --aspect 9:16 --ref "$reported" 2>"$TEST_DIR/reported_err.txt")"
if [ ! -f "$output" ] || [ ! "$output" -ef "$clip" ]; then
  echo "FAIL: a 400x736 opening frame should count as 9:16" >&2
  echo "Actual: $output" >&2
  exit 1
fi
reported_err="$(cat "$TEST_DIR/reported_err.txt")"
if [[ "$reported_err" == *"but --aspect"* ]]; then
  echo "FAIL: 400x736 should not conflict with --aspect 9:16" >&2
  echo "Actual: $reported_err" >&2
  exit 1
fi

plain="$TEST_DIR/not-an-image.png"
printf 'not a png\n' > "$plain"
output="$(run_cli -p grok --video-gen "a paper plane banks" --aspect 16:9 --ref "$plain" 2>"$TEST_DIR/unread_err.txt")"
if [ ! -f "$output" ] || [ ! "$output" -ef "$clip" ]; then
  echo "FAIL: an unreadable opening frame should still print the saved video" >&2
  echo "Actual: $output" >&2
  exit 1
fi
if [[ "$output" == *"could not read"* ]]; then
  echo "FAIL: the unreadable-frame note should stay on stderr" >&2
  echo "Actual: $output" >&2
  exit 1
fi
unread_err="$(cat "$TEST_DIR/unread_err.txt")"
assert_contains "$unread_err" "could not read the size" \
  "an unreadable opening frame should say the size was not read"
assert_contains "$unread_err" "not applied" \
  "an unreadable opening frame should say --aspect is not applied"
assert_contains "$unread_err" "first --ref" \
  "an unreadable opening frame should say the first reference sets the shape"

echo "PASS: --video-gen routes to grok and rejects the other modes"
