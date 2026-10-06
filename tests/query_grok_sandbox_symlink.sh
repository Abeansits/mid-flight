#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=grok
grok_model=grok-4
grok_effort=high
EOF

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
We are testing Grok sandbox classification.

## Question
Can MidFlight tell a socket symlink from a DNS failure?
EOF
)"

write_grok_failure_stub() {
  local stderr_text="$1"

  printf '%s\n' "$stderr_text" > "$TEST_DIR/grok_stderr.txt"

  cat > "$TEST_DIR/bin/grok" <<EOF
#!/bin/bash

set -euo pipefail

sandbox=""

while [ \$# -gt 0 ]; do
  case "\$1" in
    --sandbox) sandbox="\$2"; shift 2 ;;
    -p|--single|-m|--model|--effort|--output-format) shift 2 ;;
    *) shift ;;
  esac
done

printf '%s' "\$sandbox" > "$TEST_DIR/grok_sandbox.txt"
cat "$TEST_DIR/grok_stderr.txt" >&2
exit 1
EOF
  chmod +x "$TEST_DIR/bin/grok"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    echo "FAIL: $message" >&2
    echo "Unexpected: $needle" >&2
    exit 1
  fi
}

write_grok_failure_stub "permission denied
warning: sandbox could not be applied: socket deny resolution failed: could not resolve runtime-socket deny path /var/run/docker.sock: endpoint is a symlink
error: could not apply the 'read-only' sandbox profile; see the warning above for the cause. Refusing to start with its protections missing."

set +e
output="$(run_query "$QUERY_FILE" consult 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: query.sh should fail when Grok refuses the read-only sandbox" >&2
  exit 1
fi

assert_eq "read-only" "$(cat "$TEST_DIR/grok_sandbox.txt")" \
  "consult must still pass --sandbox read-only when the socket is a symlink"
assert_contains "$output" \
  "Error: Grok refused to start the read-only sandbox because a runtime socket path is a symlink" \
  "symlink socket refusal should be a sandbox-refusal error"
assert_contains "$output" "\"/var/run/docker.sock\"" \
  "sandbox-refusal error should quote the docker.sock path from the log"
assert_contains "$output" "grok sandbox refusal" \
  "symlink socket refusal should be logged as a sandbox refusal"
assert_not_contains "$output" "failed because of a network issue" \
  "symlink socket refusal must not use the network-error text"
assert_not_contains "$output" "network error" \
  "symlink socket refusal must not be classified as a network error"
assert_not_contains "$output" "authentication failed" \
  "an earlier permission denied line must not label a socket symlink as auth"

write_grok_failure_stub "curl: (6) Could not resolve host: api.x.ai"

set +e
output="$(run_query "$QUERY_FILE" consult 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: query.sh should fail when Grok cannot resolve a host" >&2
  exit 1
fi

assert_contains "$output" "Error: Grok failed because of a network issue." \
  "DNS-style could not resolve host should stay a network error"
assert_contains "$output" "grok network error" \
  "DNS-style failure should be logged as a network error"
assert_not_contains "$output" "refused to start the read-only sandbox" \
  "DNS-style could not resolve host must not be a sandbox refusal"

echo "PASS: Grok socket symlink refusals are sandbox refusals and DNS failures stay network errors"
