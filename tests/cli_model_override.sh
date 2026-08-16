#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

# Stub a provider CLI that records the model it was invoked with into
# $TEST_DIR/<provider>_model.txt. Each arm mirrors the flags that
# scripts/lib/providers.sh actually passes to that CLI.
write_model_probe() {
  local provider="$1"

  case "$provider" in
    codex)
      cat > "$TEST_DIR/bin/codex" <<'EOF'
#!/bin/bash
set -euo pipefail
model=""
output_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    -o|--output-last-message) output_file="$2"; shift 2 ;;
    -c|--sandbox) shift 2 ;;
    --skip-git-repo-check) shift ;;
    *) shift ;;
  esac
done
printf '%s' "$model" > "$TEST_DIR/codex_model.txt"
printf 'probe-ok\n' > "$output_file"
EOF
      ;;
    gemini)
      cat > "$TEST_DIR/bin/gemini" <<'EOF'
#!/bin/bash
set -euo pipefail
model=""
while [ $# -gt 0 ]; do
  case "$1" in
    -m) model="$2"; shift 2 ;;
    -p|--include-directories|--output-format) shift 2 ;;
    *) shift ;;
  esac
done
printf '%s' "$model" > "$TEST_DIR/gemini_model.txt"
printf 'probe-ok\n'
EOF
      ;;
    opencode)
      cat > "$TEST_DIR/bin/opencode" <<'EOF'
#!/bin/bash
set -euo pipefail
model=""
while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    --variant|--format|--dir) shift 2 ;;
    *) shift ;;
  esac
done
printf '%s' "$model" > "$TEST_DIR/opencode_model.txt"
printf 'probe-ok\n'
EOF
      ;;
    oz)
      cat > "$TEST_DIR/bin/oz" <<'EOF'
#!/bin/bash
set -euo pipefail
model=""
while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    --prompt|--output-format|--profile|-C) shift 2 ;;
    *) shift ;;
  esac
done
printf '%s' "$model" > "$TEST_DIR/oz_model.txt"
printf 'probe-ok\n'
EOF
      ;;
    *)
      echo "FAIL: no model probe for provider '$provider'" >&2
      exit 1
      ;;
  esac

  chmod +x "$TEST_DIR/bin/$provider"
}

echo "Test 1: --model without -p overrides the configured provider's model"

write_config <<'EOF'
provider=gemini
gemini_model=gemini-2.5-pro
EOF

write_model_probe gemini

run_cli --model gemini-2.5-flash "test question" >/dev/null

assert_eq "gemini-2.5-flash" "$(cat "$TEST_DIR/gemini_model.txt")" \
  "--model should override gemini_model for the configured provider"

assert_eq "gemini_model=gemini-2.5-pro" \
  "$(grep '^gemini_model=' "$HOME/.config/mid-flight/config")" \
  "--model should not modify the user's real config"

echo "Test 2: -p codex --model sets codex_model"

write_model_probe codex

run_cli -p codex --model gpt-5 "test question" >/dev/null

assert_eq "gpt-5" "$(cat "$TEST_DIR/codex_model.txt")" \
  "--model with -p codex should set codex_model"

echo "Test 3: -p opencode --model sets opencode_model"

write_model_probe opencode

run_cli -p opencode --model anthropic/claude-sonnet-4-0 "test question" >/dev/null

assert_eq "anthropic/claude-sonnet-4-0" "$(cat "$TEST_DIR/opencode_model.txt")" \
  "--model with -p opencode should set opencode_model"

echo "Test 4: -p oz --model sets oz_model"

write_model_probe oz

run_cli -p oz --model auto-genius "test question" >/dev/null

assert_eq "auto-genius" "$(cat "$TEST_DIR/oz_model.txt")" \
  "--model with -p oz should set oz_model"

echo "Test 5: --model in video mode maps to gemini_model"

# Video mode always runs on gemini regardless of the configured provider, so
# --model has to resolve against gemini rather than the config's provider.
write_config <<'EOF'
provider=codex
codex_model=gpt-5.4
gemini_model=gemini-2.5-pro
EOF

rm -f "$TEST_DIR/gemini_model.txt" "$TEST_DIR/codex_model.txt"
write_model_probe gemini
printf 'fake-video-bytes\n' > "$TEST_DIR/clip.mp4"

run_cli --video "$TEST_DIR/clip.mp4" --model gemini-2.5-flash "describe this" >/dev/null

assert_eq "gemini-2.5-flash" "$(cat "$TEST_DIR/gemini_model.txt")" \
  "--model in video mode should set gemini_model"

if [ -f "$TEST_DIR/codex_model.txt" ]; then
  echo "FAIL: video mode must not route --model to codex_model" >&2
  exit 1
fi

echo "Test 6: --model against an unsupported provider is rejected"

write_config <<'EOF'
provider=bogus
EOF

set +e
err="$(run_cli --model some-model "test question" 2>&1)"
status=$?
set -e

assert_eq "2" "$status" "--model with an unsupported provider should exit 2"
assert_contains "$err" "unknown provider 'bogus'" \
  "the failure should name the provider it could not map"

echo "PASS: --model maps to the active provider's model key"
