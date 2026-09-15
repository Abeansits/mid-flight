#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
source "$ROOT_DIR/tests/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

GUARD="$ROOT_DIR/hosts/codex/scripts/prefer-non-codex-provider.sh"
RUN="$ROOT_DIR/hosts/codex/scripts/run-query.sh"

# Default config is provider=codex; with agy on PATH → prefer agy
write_agy_stub "from-agy"
write_config <<'CFG'
provider=codex
CFG

out="$(bash "$GUARD" 2>"$TEST_DIR/warn.txt")"
assert_eq "agy" "$out" "circular default should pick agy when available"
assert_contains "$(cat "$TEST_DIR/warn.txt")" "circular" "should warn about circular provider"

# Prefer order: agy before opencode
cat > "$TEST_DIR/bin/opencode" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$TEST_DIR/bin/opencode"
out="$(bash "$GUARD" 2>/dev/null)"
assert_eq "agy" "$out" "agy should beat opencode"

# Without agy, pick opencode
rm -f "$TEST_DIR/bin/agy"
out="$(bash "$GUARD" 2>/dev/null)"
assert_eq "opencode" "$out" "fallback to opencode"

# Explicit non-codex config is left alone
write_config <<'CFG'
provider=oz
CFG
out="$(bash "$GUARD" 2>/dev/null)"
assert_eq "oz" "$out" "non-codex config unchanged"

# Override allows codex
write_config <<'CFG'
provider=codex
CFG
rm -f "$TEST_DIR/bin/opencode"
export MIDFLIGHT_ALLOW_CODEX_PROVIDER=1
out="$(bash "$GUARD" 2>"$TEST_DIR/warn2.txt")"
assert_eq "codex" "$out" "override allows codex"
assert_contains "$(cat "$TEST_DIR/warn2.txt")" "allowing provider=codex" "override warning"
unset MIDFLIGHT_ALLOW_CODEX_PROVIDER

# Refuse when no alternate and no override
set +e
err="$(bash "$GUARD" 2>&1)"
status=$?
set -e
assert_eq "1" "$status" "refuse circular with no alternate"
assert_contains "$err" "refused circular" "refuse message"

# End-to-end: run-query with stubs uses agy, not the default codex provider
write_agy_stub "host-agy-ok"
write_codex_stub "host-codex-ok"
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

result="$(bash "$RUN" --start-dir "$ROOT_DIR" "$query" consult 2>"$TEST_DIR/run_warn.txt")"
assert_eq "host-agy-ok" "$result" "run-query should route to agy under circular guard"
assert_contains "$(cat "$TEST_DIR/run_warn.txt")" "circular" "run-query warns"

# --allow-codex-provider forces codex
result="$(bash "$RUN" --allow-codex-provider --start-dir "$ROOT_DIR" "$query" consult 2>/dev/null)"
assert_eq "host-codex-ok" "$result" "allow flag forces codex"

# --provider codex without allow fails
set +e
err="$(bash "$RUN" --provider codex --start-dir "$ROOT_DIR" "$query" consult 2>&1)"
status=$?
set -e
assert_eq "1" "$status" "explicit codex without allow fails"
assert_contains "$err" "requires --allow-codex-provider" "explicit codex error"

echo "PASS: host_codex_circular_provider"
