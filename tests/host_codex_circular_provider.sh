#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
source "$ROOT_DIR/tests/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

GUARD="$ROOT_DIR/hosts/codex/scripts/prefer-non-codex-provider.sh"
RUN="$ROOT_DIR/hosts/codex/scripts/run-query.sh"
SKILL_RUN="$ROOT_DIR/hosts/codex/skills/midflight/scripts/run.sh"

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

# ---------------------------------------------------------------------------
# Blocker 1: skill run.sh via MIDFLIGHT_ROOT only (no midflight on PATH).
# Isolated skill copy (no adjacent hosts/codex/scripts/run-query.sh) so the
# standalone path is exercised. Stub query.sh records HOME config provider
# (query.sh has no -p; override is via temp HOME) and echoes argv.
# ---------------------------------------------------------------------------
fake_root="$TEST_DIR/fake-midflight-root"
mkdir -p "$fake_root/scripts" "$TEST_DIR/skill-only/scripts"
cp "$SKILL_RUN" "$TEST_DIR/skill-only/scripts/run.sh"
cp "$ROOT_DIR/hosts/codex/skills/midflight/scripts/prefer-non-codex-provider.sh" \
  "$TEST_DIR/skill-only/scripts/prefer-non-codex-provider.sh"
chmod +x "$TEST_DIR/skill-only/scripts/"*.sh

cat > "$fake_root/scripts/query.sh" <<'STUB'
#!/bin/bash
set -euo pipefail
# Record provider from staged HOME config (skill run.sh override).
if [ -f "$HOME/.config/mid-flight/config" ]; then
  grep '^provider=' "$HOME/.config/mid-flight/config" || true
fi
printf 'ARGS:'
printf ' %q' "$@"
printf '\n'
STUB
chmod +x "$fake_root/scripts/query.sh"

write_agy_stub "unused-agy"
write_config <<'CFG'
provider=codex
CFG

export PATH="/usr/bin:/bin:$TEST_DIR/bin"
# Ensure midflight is NOT on PATH
rm -f "$TEST_DIR/bin/midflight"
export MIDFLIGHT_ROOT="$fake_root"

out="$(bash "$TEST_DIR/skill-only/scripts/run.sh" "$query" consult 2>"$TEST_DIR/skill_root_warn.txt")"
assert_contains "$out" "provider=agy" "MIDFLIGHT_ROOT path must stage non-codex provider into query HOME config"
assert_contains "$out" "ARGS:" "stub query.sh should receive positional args"
assert_contains "$(cat "$TEST_DIR/skill_root_warn.txt")" "circular" "skill MIDFLIGHT_ROOT path should warn"

# ---------------------------------------------------------------------------
# Blocker 2: midflight on PATH, no GUARD scripts → --provider codex still fails
# without --allow-codex-provider.
# ---------------------------------------------------------------------------
mkdir -p "$TEST_DIR/skill-no-guard/scripts"
# Isolated skill: run.sh present, but no bundled prefer script and no host tree.
cp "$SKILL_RUN" "$TEST_DIR/skill-no-guard/scripts/run.sh"
chmod +x "$TEST_DIR/skill-no-guard/scripts/run.sh"

cat > "$TEST_DIR/bin/midflight" <<'STUB'
#!/bin/bash
# Echo args so we can see if -p codex would have been passed
printf 'MF_ARGS:'
printf ' %q' "$@"
printf '\n'
STUB
chmod +x "$TEST_DIR/bin/midflight"
export PATH="$TEST_DIR/bin:/usr/bin:/bin"
unset MIDFLIGHT_ROOT

set +e
err="$(bash "$TEST_DIR/skill-no-guard/scripts/run.sh" --provider codex "$query" consult 2>&1)"
status=$?
set -e
assert_eq "1" "$status" "standalone --provider codex without allow must fail (no GUARD)"
assert_contains "$err" "requires --allow-codex-provider" "standalone explicit codex error"

# With allow flag, midflight receives -p codex
out="$(bash "$TEST_DIR/skill-no-guard/scripts/run.sh" --allow-codex-provider --provider codex "$query" consult 2>/dev/null)"
assert_contains "$out" "-p" "allow path passes -p to midflight"
assert_contains "$out" "codex" "allow path passes codex provider"

# --provider without value should error clearly under set -u
set +e
err="$(bash "$TEST_DIR/skill-no-guard/scripts/run.sh" --provider 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "--provider without value exits 2"
assert_contains "$err" "--provider needs a value" "--provider missing value message"

echo "PASS: host_codex_circular_provider"
