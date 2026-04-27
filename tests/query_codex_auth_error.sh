#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
EOF

cat > "$TEST_DIR/bin/codex" <<'EOF'
#!/bin/bash

set -euo pipefail

echo "Unauthorized: invalid API key" >&2
exit 1
EOF

chmod +x "$TEST_DIR/bin/codex"

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
We are testing provider auth failures.

## Question
Can MidFlight surface a better error?
EOF
)"

set +e
output="$(run_query "$QUERY_FILE" consult 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: query.sh should fail when Codex authentication fails" >&2
  exit 1
fi

assert_contains "$output" "Error: Codex authentication failed." "auth failures should be classified clearly"
assert_contains "$output" "Unauthorized: invalid API key" "auth failures should preserve the provider detail"

echo "PASS: provider auth failures are surfaced with a specific error"
