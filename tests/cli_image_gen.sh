#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

# Configured Codex keeps the image prompt and writes with workspace-write.
write_config <<'EOF'
provider=codex
codex_model=test-codex
EOF

write_codex_stub "/tmp/paper-plane.png"

output="$(run_cli --image-gen "a paper plane over a fjord")"
assert_eq "/tmp/paper-plane.png" "$output" "--image-gen should print the codex image path"

prompt="$(cat "$TEST_DIR/codex_prompt.txt")"
assert_contains "$prompt" "a paper plane over a fjord" \
  "the codex prompt should include the image description"
assert_contains "$prompt" "\$imagegen" \
  "the codex prompt should invoke \$imagegen"
assert_contains "$prompt" "absolute path" \
  "the codex prompt should ask for only the file path"
assert_eq "workspace-write" "$(cat "$TEST_DIR/codex_sandbox.txt")" \
  "image-gen codex sandbox should be workspace-write"

# A non-image provider falls back to grok when that CLI is on PATH.
write_config <<'EOF'
provider=agy
agy_model=test-agy
EOF

write_grok_stub "/tmp/fjord.png"

output="$(run_cli --image-gen "a paper plane over a fjord")"
assert_eq "/tmp/fjord.png" "$output" "agy config should fall back to grok for --image-gen"
assert_eq "yes" "$(cat "$TEST_DIR/grok_always_approve.txt")" \
  "image-gen grok must pass --always-approve"
grok_prompt="$(cat "$TEST_DIR/grok_prompt.txt")"
assert_contains "$grok_prompt" "image_gen" "the grok prompt should name image_gen"
assert_contains "$grok_prompt" "a paper plane over a fjord" \
  "the grok prompt should include the image description"

# -p selects Codex even when config says grok.
write_config <<'EOF'
provider=grok
grok_model=grok-4
EOF

write_codex_stub "/tmp/from-codex.png"
output="$(run_cli -p codex --image-gen "a red kite")"
assert_eq "/tmp/from-codex.png" "$output" "-p codex should override a grok config"
assert_contains "$(cat "$TEST_DIR/codex_prompt.txt")" "a red kite" \
  "the overridden codex prompt should include the description"

# Usage errors.
set +e
err="$(run_cli -p gemini --image-gen "a cat" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "-p gemini --image-gen should exit 2"
assert_contains "$err" "supports codex and grok" "-p gemini should name the supported providers"

set +e
err="$(run_cli --image-gen 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "--image-gen without a prompt should exit 2"
assert_contains "$err" "requires a prompt" "a missing prompt should be explained"

set +e
err="$(run_cli --image-gen "a cat" --video "$TEST_DIR/clip.mp4" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "--image-gen plus --video should exit 2"
assert_contains "$err" "cannot be combined with --video" "--image-gen plus --video should be explained"

set +e
err="$(run_cli --dual agy --image-gen "a cat" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "--image-gen plus --dual should exit 2"
assert_contains "$err" "consult-only" "--image-gen plus --dual should stay consult-only"

set +e
err="$(run_cli --image-gen "a cat" "and also this" 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "a separate question with --image-gen should exit 2"
assert_contains "$err" "not as a separate question" "a separate question should be explained"

# -p uses a temp HOME. The image is stored through the symlinked ~/.grok, and
# the printed path must be that lasting file, not the temp HOME path.
mkdir -p "$HOME/.grok/images"
cat > "$TEST_DIR/bin/grok" <<'EOF'
#!/bin/bash
set -euo pipefail
target="$HOME/.grok/images/plane.jpg"
mkdir -p "$(dirname "$target")"
printf 'jpeg\n' > "$target"
printf '%s\n' "$target"
EOF
chmod +x "$TEST_DIR/bin/grok"

output="$(run_cli -p grok --image-gen "a paper plane over a fjord")"
lasting="$HOME/.grok/images/plane.jpg"
if [ ! -f "$output" ] || [ ! "$output" -ef "$lasting" ]; then
  echo "FAIL: --image-gen should print the path that survives the temp HOME" >&2
  echo "Expected file: $lasting" >&2
  echo "Actual:        $output" >&2
  exit 1
fi
assert_eq "jpeg" "$(cat "$output")" "the printed path should be the saved image"
if [[ "$output" == *midflight-cli* ]]; then
  echo "FAIL: printed path still points at the temp HOME" >&2
  exit 1
fi

# The model sometimes adds a sentence and glues the temp path to it.
cat > "$TEST_DIR/bin/grok" <<'EOF'
#!/bin/bash
set -euo pipefail
target="$HOME/.grok/images/boat.jpg"
mkdir -p "$(dirname "$target")"
printf 'boat\n' > "$target"
printf 'Done. The file is %s.\n' "$target"
EOF
chmod +x "$TEST_DIR/bin/grok"

output="$(run_cli -p grok --image-gen "a red paper boat")"
lasting="$HOME/.grok/images/boat.jpg"
if [ ! -f "$output" ] || [ ! "$output" -ef "$lasting" ]; then
  echo "FAIL: a sentence around the path should still resolve to the saved file" >&2
  echo "Expected file: $lasting" >&2
  echo "Actual:        $output" >&2
  exit 1
fi
assert_eq "boat" "$(cat "$output")" "the prose case should print only the saved file"
if [[ "$output" == *midflight-cli* ]] || [[ "$output" == *"Done."* ]]; then
  echo "FAIL: stdout should be only the resolved path" >&2
  echo "Actual: $output" >&2
  exit 1
fi

echo "PASS: --image-gen routes to codex or grok and rejects the other modes"
