#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
codex_model=test-model
codex_reasoning_effort=high
gemini_model=test-gemini
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

output="$(run_check_config)"

assert_contains "$output" "[ok] Config syntax and values look valid" "check-config should validate a healthy config"
assert_contains "$output" "[ok] Configured provider (codex):" "check-config should verify the active provider"
assert_contains "$output" "PASS: MidFlight config looks good" "check-config should succeed when the setup is healthy"

echo "PASS: check-config succeeds for a healthy MidFlight setup"
