#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
EOF

QUERY_FILE="$(
  write_query_file <<'EOF'
## Context
Testing provider availability.

## Question
Can we show a good install hint?
EOF
)"

set +e
output="$(run_query "$QUERY_FILE" consult 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: query.sh should fail when the provider CLI is missing" >&2
  exit 1
fi

assert_contains "$output" "Error: 'codex' CLI not found." "missing provider should produce an install hint"

echo "PASS: missing providers fail early with a clear install message"
