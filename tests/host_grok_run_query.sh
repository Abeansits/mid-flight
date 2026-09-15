#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
source "$ROOT_DIR/tests/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

RUN="$ROOT_DIR/hosts/grok/scripts/run-query.sh"

# Default provider=codex is fine from Grok — no circular rewrite
write_codex_stub "host-codex-ok"
write_agy_stub "host-agy-ok"
write_config <<'CFG'
provider=codex
CFG
query="$(write_query_file <<'Q'
## Context
x
## Question
y
Q
)"

result="$(bash "$RUN" --start-dir "$ROOT_DIR" "$query" consult 2>/dev/null)"
assert_eq "host-codex-ok" "$result" "Grok host should use configured codex provider"

# --provider overrides
result="$(bash "$RUN" --provider agy --start-dir "$ROOT_DIR" "$query" consult 2>/dev/null)"
assert_eq "host-agy-ok" "$result" "--provider agy forces agy"

echo "PASS: host_grok_run_query"
