#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
source "$ROOT_DIR/tests/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

GUARD="$ROOT_DIR/hosts/grok/scripts/prefer-non-grok-provider.sh"
RUN="$ROOT_DIR/hosts/grok/scripts/run-query.sh"
SKILL_RUN="$ROOT_DIR/hosts/grok/skills/midflight/scripts/run.sh"

# Default config is provider=codex; leave alone
write_codex_stub "from-codex"
write_config <<'CFG'
provider=codex
CFG

out="$(bash "$GUARD" 2>"$TEST_DIR/warn.txt")"
assert_eq "codex" "$out" "non-grok config should be left alone"
[ ! -s "$TEST_DIR/warn.txt" ] || {
  echo "FAIL: non-grok config should not warn" >&2
  exit 1
}

# Circular default: provider=grok with codex on PATH → prefer codex
write_config <<'CFG'
provider=grok
CFG
out="$(bash "$GUARD" 2>"$TEST_DIR/warn.txt")"
assert_eq "codex" "$out" "circular default should pick codex when available"
assert_contains "$(cat "$TEST_DIR/warn.txt")" "circular" "should warn about circular provider"

# Prefer order: codex before agy
write_agy_stub "unused"
out="$(bash "$GUARD" 2>/dev/null)"
assert_eq "codex" "$out" "codex should beat agy"

# Without codex, pick agy
rm -f "$TEST_DIR/bin/codex"
out="$(bash "$GUARD" 2>/dev/null)"
assert_eq "agy" "$out" "fallback to agy"

# Explicit non-grok config is left alone
write_config <<'CFG'
provider=oz
CFG
out="$(bash "$GUARD" 2>/dev/null)"
assert_eq "oz" "$out" "non-grok config unchanged"

# Override allows grok
write_config <<'CFG'
provider=grok
CFG
rm -f "$TEST_DIR/bin/agy"
export MIDFLIGHT_ALLOW_GROK_PROVIDER=1
# Need a stub so ensure later; guard only checks PATH for alternates
out="$(bash "$GUARD" 2>"$TEST_DIR/warn2.txt")"
assert_eq "grok" "$out" "override allows grok"
assert_contains "$(cat "$TEST_DIR/warn2.txt")" "allowing provider=grok" "override warning"
unset MIDFLIGHT_ALLOW_GROK_PROVIDER

# Refuse when no alternate and no override
set +e
err="$(bash "$GUARD" 2>&1)"
status=$?
set -e
assert_eq "1" "$status" "refuse circular with no alternate"
assert_contains "$err" "refused circular" "refuse message"

# End-to-end: run-query with stubs uses codex, not configured grok
write_codex_stub "host-codex-ok"
write_grok_stub "host-grok-ok"
write_config <<'CFG'
provider=grok
CFG
query="$(write_query_file <<'Q'
## Context
x
## Question
y
Q
)"

result="$(bash "$RUN" --start-dir "$ROOT_DIR" "$query" consult 2>"$TEST_DIR/run_warn.txt")"
assert_eq "host-codex-ok" "$result" "run-query should route to codex under circular guard"
assert_contains "$(cat "$TEST_DIR/run_warn.txt")" "circular" "run-query warns"

# --allow-grok-provider forces grok
result="$(bash "$RUN" --allow-grok-provider --start-dir "$ROOT_DIR" "$query" consult 2>/dev/null)"
assert_eq "host-grok-ok" "$result" "allow flag forces grok"

# --provider grok without allow fails
set +e
err="$(bash "$RUN" --provider grok --start-dir "$ROOT_DIR" "$query" consult 2>&1)"
status=$?
set -e
assert_eq "1" "$status" "explicit grok without allow fails"
assert_contains "$err" "requires --allow-grok-provider" "explicit grok error"

# ---------------------------------------------------------------------------
# Blocker 1: skill run.sh via MIDFLIGHT_ROOT only (no midflight on PATH).
# ---------------------------------------------------------------------------
fake_root="$TEST_DIR/fake-midflight-root"
mkdir -p "$fake_root/scripts" "$TEST_DIR/skill-only/scripts"
cp "$SKILL_RUN" "$TEST_DIR/skill-only/scripts/run.sh"
cp "$ROOT_DIR/hosts/grok/skills/midflight/scripts/prefer-non-grok-provider.sh" \
  "$TEST_DIR/skill-only/scripts/prefer-non-grok-provider.sh"
chmod +x "$TEST_DIR/skill-only/scripts/"*.sh

cat > "$fake_root/scripts/query.sh" <<'STUB'
#!/bin/bash
set -euo pipefail
if [ -f "$HOME/.config/mid-flight/config" ]; then
  grep '^provider=' "$HOME/.config/mid-flight/config" || true
fi
printf 'ARGS:'
printf ' %q' "$@"
printf '\n'
STUB
chmod +x "$fake_root/scripts/query.sh"

write_codex_stub "unused-codex"
write_config <<'CFG'
provider=grok
CFG

export PATH="/usr/bin:/bin:$TEST_DIR/bin"
rm -f "$TEST_DIR/bin/midflight"
export MIDFLIGHT_ROOT="$fake_root"

out="$(bash "$TEST_DIR/skill-only/scripts/run.sh" "$query" consult 2>"$TEST_DIR/skill_root_warn.txt")"
assert_contains "$out" "provider=codex" "MIDFLIGHT_ROOT path must stage non-grok provider into query HOME config"
assert_contains "$out" "ARGS:" "stub query.sh should receive positional args"
assert_contains "$(cat "$TEST_DIR/skill_root_warn.txt")" "circular" "skill MIDFLIGHT_ROOT path should warn"

# ---------------------------------------------------------------------------
# Blocker 2: midflight on PATH, no GUARD scripts → --provider grok still fails
# without --allow-grok-provider.
# ---------------------------------------------------------------------------
mkdir -p "$TEST_DIR/skill-no-guard/scripts"
cp "$SKILL_RUN" "$TEST_DIR/skill-no-guard/scripts/run.sh"
chmod +x "$TEST_DIR/skill-no-guard/scripts/run.sh"

cat > "$TEST_DIR/bin/midflight" <<'STUB'
#!/bin/bash
printf 'MF_ARGS:'
printf ' %q' "$@"
printf '\n'
STUB
chmod +x "$TEST_DIR/bin/midflight"
export PATH="$TEST_DIR/bin:/usr/bin:/bin"
unset MIDFLIGHT_ROOT

set +e
err="$(bash "$TEST_DIR/skill-no-guard/scripts/run.sh" --provider grok "$query" consult 2>&1)"
status=$?
set -e
assert_eq "1" "$status" "standalone --provider grok without allow must fail (no GUARD)"
assert_contains "$err" "requires --allow-grok-provider" "standalone explicit grok error"

# With allow flag, midflight receives -p grok
out="$(bash "$TEST_DIR/skill-no-guard/scripts/run.sh" --allow-grok-provider --provider grok "$query" consult 2>/dev/null)"
assert_contains "$out" "-p" "allow path passes -p to midflight"
assert_contains "$out" "grok" "allow path passes grok provider"

# --provider without value should error clearly under set -u
set +e
err="$(bash "$TEST_DIR/skill-no-guard/scripts/run.sh" --provider 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "--provider without value exits 2"
assert_contains "$err" "--provider needs a value" "--provider missing value message"

echo "PASS: host_grok_circular_provider"
