#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

cat > "$HOME/.config/mid-flight/config" <<'EOF'
provider = codex
EOF

cat > "$TEST_DIR/bin/codex" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$TEST_DIR/bin/codex"

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
We are testing config validation.

## Question
Will MidFlight fail before invoking the provider?
EOF
)"

set +e
output="$(run_query "$QUERY_FILE" consult 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: query.sh should fail when the config is invalid" >&2
  exit 1
fi

assert_contains "$output" "Error: MidFlight config is invalid." "query.sh should fail early on invalid config"
assert_contains "$output" "Invalid config syntax at line 1" "query.sh should include the validation issue"

echo "PASS: query.sh fails early on invalid MidFlight config"
