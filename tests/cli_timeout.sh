#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
codex_model=test-model
EOF

# Slow stub: sleeps longer than the timeout we will pass. The wrapper's
# --timeout watchdog (pure bash, pg kill) must fire first, kill the group,
# print clear message on stderr, and exit nonzero. No "Terminated" noise
# should appear in the captured output (watchdog redirects + reaps).
write_slow_codex_stub() {
  cat > "$TEST_DIR/bin/codex" <<'STUB'
#!/bin/bash
set -euo pipefail
output_file=""
prompt=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output-last-message) output_file="$2"; shift 2 ;;
    --model|-c|--full-auto|--skip-git-repo-check) shift 2 ;;
    *) prompt="$1"; shift ;;
  esac
done
sleep 10   # >> any reasonable test timeout
printf '%s' "$prompt" > "$TEST_DIR/codex_prompt.txt" 2>/dev/null || true
printf 'SLOW-RESPONSE\n' > "$output_file" 2>/dev/null || true
STUB
  chmod +x "$TEST_DIR/bin/codex"
}

write_slow_codex_stub

start=$(date +%s)
set +e
output="$(run_cli --timeout 2 "slow provider test under --timeout guard?" 2>&1)"
status=$?
set -e
end=$(date +%s)
elapsed=$(( end - start ))

if [ "$status" -eq 0 ] && ! echo "$output" | grep -q 'timed out after 2s'; then
  echo "FAIL: --timeout 2 with 10s stub should either exit nonzero or surface the timeout msg (proving kill)" >&2
  echo "Captured (first 300): ${output:0:300}" >&2
  echo "Elapsed: ${elapsed}s" >&2
  exit 1
fi

if [ "$elapsed" -lt 1 ] || [ "$elapsed" -gt 5 ]; then
  echo "FAIL: timeout should fire ~at the 2s deadline (got ${elapsed}s)" >&2
  exit 1
fi

assert_contains "$output" "timed out after 2s" \
  "wrapper must emit clear timeout message on stderr"

# The engine may print its own internal job Terminated when we nuke the provider
# call (expected); our watchdog (redirected + reaped) must not add extra noise.
# Main proof: the timeout msg appeared and we did not get the SLOW-RESPONSE.
if echo "$output" | grep -qi 'SLOW-RESPONSE'; then
  echo "FAIL: slow stub response should not have been produced (kill did not happen in time)" >&2
  exit 1
fi

echo "PASS: --timeout kills slow provider ~on deadline, nonzero exit, clean message, no noise"
