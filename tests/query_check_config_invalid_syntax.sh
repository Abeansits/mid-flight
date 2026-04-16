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

cat > "$TEST_DIR/bin/gemini" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$TEST_DIR/bin/codex" "$TEST_DIR/bin/gemini"

set +e
output="$(run_check_config 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: check-config should fail on invalid config syntax" >&2
  exit 1
fi

assert_contains "$output" "Invalid config syntax at line 1" "check-config should report malformed key/value lines"
assert_contains "$output" "FAIL: MidFlight config needs attention" "check-config should fail on invalid syntax"

echo "PASS: check-config fails clearly on invalid config syntax"
