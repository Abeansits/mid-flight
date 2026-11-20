#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT
hide_system_tools yt-dlp ffmpeg ffprobe

write_config <<'EOF2'
provider=codex
EOF2

write_agy_stub "video-url-ok"
write_ytdlp_stub "mp4"

URL="https://www.youtube.com/watch?v=abc123"

output="$(run_query "$URL" video "What happens in this clip?")"
add_dir="$(cat "$TEST_DIR/agy_add_dir.txt")"
captured_prompt="$(cat "$TEST_DIR/agy_prompt.txt")"
ytdlp_args="$(cat "$TEST_DIR/ytdlp_args.txt")"

assert_eq "video-url-ok" "$output" "a video link should be answered by the provider"
assert_contains "$ytdlp_args" "$URL" "yt-dlp should receive the link"
assert_contains "$ytdlp_args" "--no-playlist" "yt-dlp should fetch one video, not a playlist"
assert_contains "$ytdlp_args" "!is_live" "yt-dlp should skip live streams"
assert_contains "$ytdlp_args" "after_move:filepath" "yt-dlp should report the finished file"
assert_contains "$ytdlp_args" "--no-simulate" "asking for the path must not turn the download into a dry run"
# The stub leaves video.info.json next to the video. Staging that instead
# would show up here as video_input.json.
assert_contains "$captured_prompt" "${add_dir}/video_input.mp4" \
  "the provider should get the downloaded video by path, not the metadata next to it"
assert_contains "$captured_prompt" "What happens in this clip?" \
  "the video prompt should reach the provider"
if [[ "$captured_prompt" == *"youtube.com"* ]]; then
  echo "FAIL: the provider cannot watch a link, so the link must not be the video reference" >&2
  exit 1
fi

# Without ffmpeg there is nothing to merge streams with, so yt-dlp must be
# asked for one pre-merged file.
assert_contains "$ytdlp_args" "res:720,ext:mp4" "yt-dlp should prefer 720p"
if [[ "$ytdlp_args" == *"--merge-output-format"* ]]; then
  echo "FAIL: yt-dlp must not be asked to merge streams when ffmpeg is missing" >&2
  exit 1
fi

# With ffmpeg, separate best video and audio streams are merged to MP4.
write_ffmpeg_stubs
run_query "$URL" video "Again." >/dev/null
ytdlp_args="$(cat "$TEST_DIR/ytdlp_args.txt")"
assert_contains "$ytdlp_args" "--merge-output-format" \
  "yt-dlp should merge video and audio when ffmpeg is available"
assert_contains "$ytdlp_args" "bv*+ba/b" "yt-dlp should ask for the best video plus audio"

# A pinned Gemini provider gets the same download, referenced with @path.
write_config <<'EOF2'
provider=gemini
gemini_model=test-gemini
EOF2
write_gemini_stub "video-url-gemini-ok"
output="$(run_query "$URL" video "Gemini too.")"
assert_eq "video-url-gemini-ok" "$output" "a pinned Gemini provider should answer a video link"
gemini_prompt="$(cat "$TEST_DIR/gemini_prompt.txt")"
assert_contains "$gemini_prompt" "/video_input.mp4" "Gemini should get the downloaded file"
if [[ "$gemini_prompt" == *"youtube.com"* ]]; then
  echo "FAIL: Gemini should get the downloaded file, not the link" >&2
  exit 1
fi

echo "PASS: video links are downloaded with yt-dlp and analyzed as local files"
