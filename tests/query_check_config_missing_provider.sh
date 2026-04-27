#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=oz
oz_model=auto
oz_output_format=text
EOF

set +e
output="$(run_check_config 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: check-config should fail when the configured provider is missing" >&2
  exit 1
fi

assert_contains "$output" "[error] Configured provider (oz): not found in PATH" "check-config should fail when the active provider is missing"

echo "PASS: check-config fails clearly when the active provider CLI is missing"
