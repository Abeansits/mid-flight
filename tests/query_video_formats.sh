#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT
hide_system_tools ffmpeg ffprobe

write_config <<'EOF2'
provider=agy
EOF2
write_agy_stub "video-format-ok"

# A format the provider reads keeps its extension when staged.
MOV_FILE="$TEST_DIR/Screen Recording.MOV"
printf 'mov-bytes' > "$MOV_FILE"

output="$(run_query "$MOV_FILE" video "Describe it.")"
assert_eq "video-format-ok" "$output" "a .MOV file should be analyzed"
captured_prompt="$(cat "$TEST_DIR/agy_prompt.txt")"
add_dir="$(cat "$TEST_DIR/agy_add_dir.txt")"
assert_contains "$captured_prompt" "${add_dir}/video_input.mov" \
  "the staged file should keep a lowercased .mov extension"
assert_contains "$captured_prompt" "file-reading tool" \
  "agy should be told to open the file directly"

# A format the provider does not read is converted to MP4 when ffmpeg exists.
FLV_FILE="$TEST_DIR/capture.flv"
printf 'flv-bytes' > "$FLV_FILE"
write_ffmpeg_stubs 10

run_query "$FLV_FILE" video "Describe it." >/dev/null
assert_contains "$(cat "$TEST_DIR/ffmpeg_args.txt")" "$FLV_FILE" "ffmpeg should convert the .flv file"
assert_contains "$(cat "$TEST_DIR/agy_prompt.txt")" "/video_input.mp4" \
  "the converted file should be staged as MP4"

# Without ffmpeg the file is passed through with its own extension.
rm -f "$TEST_DIR/bin/ffmpeg" "$TEST_DIR/bin/ffprobe"
run_query "$FLV_FILE" video "Describe it." >/dev/null
assert_contains "$(cat "$TEST_DIR/agy_prompt.txt")" "/video_input.flv" \
  "without ffmpeg an unusual format should pass through unchanged"

echo "PASS: video staging keeps real extensions and converts formats the provider cannot read"
