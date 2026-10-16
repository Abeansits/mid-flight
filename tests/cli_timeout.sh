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
# print the timeout sentence on stdout (the result a harness keeps) and
# once on stderr, and exit nonzero. No "Terminated" noise should come from
# the watchdog itself (redirected + reaped).
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

stdout_file="$TEST_DIR/timeout.stdout"
stderr_file="$TEST_DIR/timeout.stderr"
start=$(date +%s)
set +e
run_cli --timeout 2 "slow provider test under --timeout guard?" >"$stdout_file" 2>"$stderr_file"
status=$?
set -e
end=$(date +%s)
elapsed=$(( end - start ))
stdout="$(cat "$stdout_file")"
stderr="$(cat "$stderr_file")"

if [ "$status" -eq 0 ]; then
  echo "FAIL: --timeout 2 with a 10s stub must exit nonzero" >&2
  echo "stdout (first 300): ${stdout:0:300}" >&2
  echo "stderr (first 300): ${stderr:0:300}" >&2
  echo "Elapsed: ${elapsed}s" >&2
  exit 1
fi

if [ "$elapsed" -lt 1 ] || [ "$elapsed" -gt 5 ]; then
  echo "FAIL: timeout should fire ~at the 2s deadline (got ${elapsed}s)" >&2
  exit 1
fi

# Stdout is captured alone. A harness that drops stderr still sees the sentence.
assert_eq "Error: timed out after 2s waiting for provider response" "$stdout" \
  "stdout should be the timeout sentence"
stderr_msgs="$(printf '%s\n' "$stderr" | grep -c 'midflight: timed out after 2s waiting for provider response' || true)"
assert_eq "1" "$stderr_msgs" "stderr timeout line should be printed once"
if printf '%s\n' "$stdout" | grep -q 'midflight: timed out after 2s'; then
  echo "FAIL: the stderr timeout line leaked onto stdout" >&2
  exit 1
fi

assert_pid_gone "$TEST_DIR/provider.pid" "provider"
assert_pid_gone "$TEST_DIR/provider_child.pid" "provider child"

# The engine may print its own internal job Terminated when we nuke the provider
# call (expected, on stderr); our watchdog (redirected + reaped) must not add
# extra noise. Main proof: the timeout sentence is on stdout and we did not
# get the SLOW-RESPONSE.
if printf '%s\n' "$stdout" "$stderr" | grep -qi 'SLOW-RESPONSE'; then
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

# One shot hides the macOS bash 3.2 race (about half of main pushes after #54).
fast_round=0
while [ "$fast_round" -lt 20 ]; do
  fast_round=$((fast_round + 1))

  set +e
  start=$(date +%s)
  output="$(run_cli --timeout 3 "test failure propagation" 2>&1)"
  status=$?
  end=$(date +%s)
  set -e
  elapsed=$(( end - start ))
  assert_eq "1" "$status" "provider failure under --timeout must exit 1 (round $fast_round)"
  assert_contains "$output" "provider exploded" "provider error should be visible (round $fast_round)"
  assert_contains "$output" "Codex query failed" "engine should report the provider failure (round $fast_round)"
  if echo "$output" | grep -q 'timed out'; then
    echo "FAIL: a fast provider failure must not be reported as a timeout (round $fast_round)" >&2
    exit 1
  fi
  if [ "$elapsed" -gt 2 ]; then
    echo "FAIL: fast provider failure under --timeout 3 took ${elapsed}s (round $fast_round)" >&2
    exit 1
  fi

  # A provider that finishes inside the deadline stays success, with no timeout line.
  write_codex_stub "fast-ok"
  set +e
  output="$(run_cli --timeout 3 "quick success under timeout?" 2>&1)"
  status=$?
  set -e
  assert_eq "0" "$status" "provider that finishes before the deadline should exit 0 (round $fast_round)"
  assert_contains "$output" "fast-ok" "successful provider output should be printed (round $fast_round)"
  if echo "$output" | grep -q 'timed out'; then
    echo "FAIL: success before the deadline must not print a timeout (round $fast_round)" >&2
    exit 1
  fi

  cat > "$TEST_DIR/bin/codex" <<'STUB'
#!/bin/bash
echo "provider exploded" >&2
exit 7
STUB
  chmod +x "$TEST_DIR/bin/codex"
done

set +e
output="$(run_cli "test failure propagation" 2>&1)"
status=$?
set -e
assert_eq "1" "$status" "provider failure without --timeout must exit 1"

echo "PASS: --timeout kills slow provider ~on deadline, nonzero exit, clean message, no noise"
