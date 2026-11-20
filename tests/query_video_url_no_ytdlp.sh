#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT
hide_system_tools yt-dlp ffmpeg ffprobe curl

write_config <<'EOF2'
provider=agy
EOF2

write_agy_stub "should-not-run"

# A watch page without yt-dlp is an error, not a guess from web search.
set +e
output="$(run_query "https://www.youtube.com/watch?v=abc123" video "Describe it." 2>/dev/null)"
status=$?
set -e

assert_eq "1" "$status" "a video link without yt-dlp should fail"
assert_contains "$output" "Video links need yt-dlp" "the error should name the missing tool"
assert_contains "$output" "brew install yt-dlp" "the error should say how to install it"
if [ -f "$TEST_DIR/agy_prompt.txt" ]; then
  echo "FAIL: the provider must not be asked about a link it cannot watch" >&2
  exit 1
fi

# A direct media link with neither downloader names both.
set +e
output="$(run_query "https://cdn.example.com/ads/spot.mp4" video "Describe it." 2>/dev/null)"
status=$?
set -e
assert_eq "1" "$status" "a direct link without yt-dlp or curl should fail"
assert_contains "$output" "need yt-dlp or curl" "the error should name both downloaders"

# A direct link to a media file falls back to curl.
cat > "$TEST_DIR/bin/curl" <<EOF2
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$@" > "$TEST_DIR/curl_args.txt"
out=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'curl-video-bytes' > "\$out"
EOF2
chmod +x "$TEST_DIR/bin/curl"
write_agy_stub "video-direct-ok"

output="$(run_query "https://cdn.example.com/ads/spot.MOV?token=abc" video "Describe it.")"
assert_eq "video-direct-ok" "$output" "a direct media link should download with curl"
assert_contains "$(cat "$TEST_DIR/curl_args.txt")" "https://cdn.example.com/ads/spot.MOV?token=abc" \
  "curl should receive the full link"
assert_contains "$(cat "$TEST_DIR/curl_args.txt")" "--speed-time" \
  "curl should give up on a download that stalls"
assert_contains "$(cat "$TEST_DIR/agy_prompt.txt")" "/video_input.mov" \
  "the staged file should keep the media extension from the link"

echo "PASS: a video link needs yt-dlp, except a direct media link that curl can fetch"
