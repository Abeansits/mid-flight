#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT
hide_system_tools ffmpeg ffprobe

VIDEO_FILE="$TEST_DIR/big.mp4"
write_sized_file "$VIDEO_FILE" 25

# 25MB is fine for agy (100MB limit) and passes through untouched.
write_config <<'EOF2'
provider=agy
EOF2
write_agy_stub "video-agy-25mb-ok"

output="$(run_query "$VIDEO_FILE" video "Describe it.")"
assert_eq "video-agy-25mb-ok" "$output" "agy should accept a 25MB video"

# 25MB is over the Gemini CLI's 20MB limit. Without ffmpeg that is an error
# that names both numbers and the fix.
write_config <<'EOF2'
provider=gemini
gemini_model=test-gemini
EOF2
write_gemini_stub "should-not-run"

set +e
output="$(run_query "$VIDEO_FILE" video "Describe it." 2>/dev/null)"
status=$?
set -e

assert_eq "1" "$status" "an oversized video without ffmpeg should fail"
assert_contains "$output" "25MB" "the error should state the file size"
assert_contains "$output" "Gemini reads at most 20MB" "the error should state the provider limit"
assert_contains "$output" "Install ffmpeg" "the error should name the fix"
if [ -f "$TEST_DIR/gemini_prompt.txt" ]; then
  echo "FAIL: Gemini must not be called with a file it cannot read" >&2
  exit 1
fi

# With ffmpeg the video is shrunk to fit and the query goes through.
write_ffmpeg_stubs 30
write_gemini_stub "video-gemini-shrunk-ok"

output="$(run_query "$VIDEO_FILE" video "Describe it.")"
assert_eq "video-gemini-shrunk-ok" "$output" "an oversized video should be shrunk and analyzed"

ffmpeg_args="$(cat "$TEST_DIR/ffmpeg_args.txt")"
assert_contains "$ffmpeg_args" "$VIDEO_FILE" "ffmpeg should read the original file"
assert_contains "$ffmpeg_args" "video_input.mp4" "ffmpeg should write the staged MP4"
# The input may be a download, so ffmpeg is held to local files and real
# container formats. A playlist named .mp4 must not pull in other files.
assert_contains "$ffmpeg_args" "-protocol_whitelist" "ffmpeg should restrict input protocols"
assert_contains "$ffmpeg_args" "-format_whitelist" "ffmpeg should restrict input formats"
# 20MB over 31s leaves about 5Mbps, which is capped at 2.5Mbps and kept at 720p.
assert_contains "$ffmpeg_args" "2500k" "the video bitrate should be capped at 2500k"
assert_contains "$ffmpeg_args" "trunc(min(720,ih)/2)*2" \
  "a generous budget should keep 720p, rounded to an even height"

# A long video gets a lower bitrate and resolution instead of an error.
write_ffmpeg_stubs 600
run_query "$VIDEO_FILE" video "Describe it." >/dev/null
ffmpeg_args="$(cat "$TEST_DIR/ffmpeg_args.txt")"
assert_contains "$ffmpeg_args" "min(360,ih)" "a tight budget should drop to 360p"
assert_contains "$ffmpeg_args" "fps=6" "a tight budget should drop the frame rate"

# A video too long to fit at any watchable bitrate is a clear error.
write_ffmpeg_stubs 7200
set +e
output="$(run_query "$VIDEO_FILE" video "Describe it." 2>/dev/null)"
status=$?
set -e
assert_eq "1" "$status" "a video too long to fit should fail"
assert_contains "$output" "too long to fit" "the error should say the video is too long"

# A file ffprobe refuses (not a video, or a script dressed as one) is an
# explained error, not a silent exit.
cat > "$TEST_DIR/bin/ffprobe" <<'EOF2'
#!/bin/bash
echo "Format not on whitelist" >&2
exit 1
EOF2
chmod +x "$TEST_DIR/bin/ffprobe"
set +e
output="$(run_query "$VIDEO_FILE" video "Describe it." 2>/dev/null)"
status=$?
set -e
assert_eq "1" "$status" "a file ffprobe cannot read should fail"
assert_contains "$output" "ffprobe could not read this video" "the error should say ffprobe refused the file"

# MIDFLIGHT_VIDEO_MAX_MB overrides the provider limit.
write_config <<'EOF2'
provider=agy
EOF2
write_agy_stub "should-not-run"
rm -f "$TEST_DIR/bin/ffmpeg" "$TEST_DIR/bin/ffprobe" "$TEST_DIR/agy_prompt.txt"

set +e
output="$(MIDFLIGHT_VIDEO_MAX_MB=10 run_query "$VIDEO_FILE" video "Describe it." 2>/dev/null)"
status=$?
set -e
assert_eq "1" "$status" "MIDFLIGHT_VIDEO_MAX_MB should lower the limit"
assert_contains "$output" "Antigravity reads at most 10MB" "the override should appear in the error"

echo "PASS: video size limits are per provider, and ffmpeg shrinks what does not fit"
