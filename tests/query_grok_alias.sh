#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'CFG'
provider=grok-build
grok_model=grok-4
CFG

write_grok_stub "alias-ok"

QUERY_FILE="$(
  write_query_file <<'Q'
## Context
Alias check.

## Question
Does provider=grok-build call grok?
Q
)"

output="$(run_query "$QUERY_FILE" consult)"

assert_eq "alias-ok" "$output" "provider=grok-build should invoke the grok binary"
assert_eq "grok-4" "$(cat "$TEST_DIR/grok_model.txt")" \
  "grok-build alias should still honor grok_model"

echo "PASS: provider=grok-build normalizes to grok"
