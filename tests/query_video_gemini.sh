#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
gemini_model=test-gemini
EOF

cat > "$TEST_DIR/bin/gemini" <<EOF
#!/bin/bash

set -euo pipefail

prompt=""
include_dir=""

while [ \$# -gt 0 ]; do
  case "\$1" in
    -p)
      prompt="\$2"
      shift 2
      ;;
    -m)
      shift 2
      ;;
    --include-directories)
      include_dir="\$2"
      shift 2
      ;;
    --sandbox)
      shift
      ;;
    --output-format)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

printf '%s' "\$prompt" > "$TEST_DIR/gemini_prompt.txt"
printf '%s' "\$include_dir" > "$TEST_DIR/gemini_include_dir.txt"
printf 'video-ok\n'
EOF

chmod +x "$TEST_DIR/bin/gemini"

VIDEO_FILE="$TEST_DIR/sample.mp4"
printf 'video-bytes' > "$VIDEO_FILE"

output="$(run_query "$VIDEO_FILE" video "Focus on pacing and overlays.")"
include_dir="$(cat "$TEST_DIR/gemini_include_dir.txt")"
captured_prompt="$(cat "$TEST_DIR/gemini_prompt.txt")"

assert_eq "video-ok" "$output" "video mode should return stubbed gemini output"
assert_contains "$captured_prompt" "Focus on pacing and overlays." "video mode should pass the custom video prompt"
assert_contains "$captured_prompt" "@${include_dir}/video_input.mp4" "video mode should reference the staged workspace video"

echo "PASS: video mode stages files into the run workspace and routes to gemini"
