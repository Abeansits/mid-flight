#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'EOF'
provider=codex
EOF

# No codex stub on PATH: the engine's own missing-provider error should surface.
set +e
output="$(run_cli "Will this fail cleanly?" 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: wrapper should fail when the provider CLI is missing" >&2
  exit 1
fi

assert_contains "$output" "Error: 'codex' CLI not found." \
  "missing provider should surface the engine's install hint"

echo "PASS: missing provider surfaces the engine's clear error through the wrapper"
