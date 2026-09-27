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
    --model|-c|--sandbox) shift 2 ;;
    --skip-git-repo-check) shift ;;
    *) prompt="$1"; shift ;;
  esac
done
printf '%s\n' "$$" > "$TEST_DIR/provider.pid"
sleep 10 &
printf '%s\n' "$!" > "$TEST_DIR/provider_child.pid"
wait
printf '%s' "$prompt" > "$TEST_DIR/codex_prompt.txt" 2>/dev/null || true
printf 'SLOW-RESPONSE\n' > "$output_file" 2>/dev/null || true
STUB
  chmod +x "$TEST_DIR/bin/codex"
}

assert_pid_gone() {
  local pid_file="$1"
  local label="$2"
  local pid

  [ -f "$pid_file" ] || {
    echo "FAIL: $label did not record a pid" >&2
    exit 1
  }
  pid="$(cat "$pid_file")"
  if kill -0 "$pid" 2>/dev/null; then
    echo "FAIL: $label pid $pid still running after timeout" >&2
    exit 1
  fi
}

write_slow_codex_stub

start=$(date +%s)
set +e
output="$(run_cli --timeout 2 "slow provider test under --timeout guard?" 2>&1)"
status=$?
set -e
end=$(date +%s)
elapsed=$(( end - start ))

if [ "$status" -eq 0 ]; then
  echo "FAIL: --timeout 2 with a 10s stub must exit nonzero" >&2
  echo "Captured (first 300): ${output:0:300}" >&2
  echo "Elapsed: ${elapsed}s" >&2
  exit 1
fi

if [ "$elapsed" -lt 1 ] || [ "$elapsed" -gt 5 ]; then
  echo "FAIL: timeout should fire ~at the 2s deadline (got ${elapsed}s)" >&2
  exit 1
fi

timeout_msgs="$(printf '%s\n' "$output" | grep -c 'timed out after 2s' || true)"
assert_eq "1" "$timeout_msgs" "timeout message should be reported once"

assert_pid_gone "$TEST_DIR/provider.pid" "provider"
assert_pid_gone "$TEST_DIR/provider_child.pid" "provider child"

# The engine may print its own internal job Terminated when we nuke the provider
# call (expected); our watchdog (redirected + reaped) must not add extra noise.
# Main proof: the timeout msg appeared and we did not get the SLOW-RESPONSE.
if echo "$output" | grep -qi 'SLOW-RESPONSE'; then
  echo "FAIL: slow stub response should not have been produced (kill did not happen in time)" >&2
  exit 1
fi

# Fast provider failure must keep the engine's nonzero status. --timeout used
# to report this as success because `wait || true` clobbered $?.
cat > "$TEST_DIR/bin/codex" <<'STUB'
#!/bin/bash
echo "provider exploded" >&2
exit 7
STUB
chmod +x "$TEST_DIR/bin/codex"

set +e
start=$(date +%s)
output="$(run_cli --timeout 3 "test failure propagation" 2>&1)"
status=$?
end=$(date +%s)
set -e
elapsed=$(( end - start ))
assert_eq "1" "$status" "provider failure under --timeout must exit 1"
assert_contains "$output" "provider exploded" "provider error should be visible"
assert_contains "$output" "Codex query failed" "engine should report the provider failure"
if echo "$output" | grep -q 'timed out'; then
  echo "FAIL: a fast provider failure must not be reported as a timeout" >&2
  exit 1
fi
if [ "$elapsed" -gt 2 ]; then
  echo "FAIL: fast provider failure under --timeout 3 took ${elapsed}s" >&2
  exit 1
fi

set +e
output="$(run_cli "test failure propagation" 2>&1)"
status=$?
set -e
assert_eq "1" "$status" "provider failure without --timeout must exit 1"

# A provider that finishes inside the deadline stays success, with no timeout line.
write_codex_stub "fast-ok"
set +e
output="$(run_cli --timeout 3 "quick success under timeout?" 2>&1)"
status=$?
set -e
assert_eq "0" "$status" "provider that finishes before the deadline should exit 0"
assert_contains "$output" "fast-ok" "successful provider output should be printed"
if echo "$output" | grep -q 'timed out'; then
  echo "FAIL: success before the deadline must not print a timeout" >&2
  exit 1
fi

echo "PASS: --timeout kills slow provider ~on deadline, nonzero exit, clean message, no noise"
