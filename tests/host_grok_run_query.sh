#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
source "$ROOT_DIR/tests/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

RUN="$ROOT_DIR/hosts/grok/scripts/run-query.sh"
SKILL_RUN="$ROOT_DIR/hosts/grok/skills/midflight/scripts/run.sh"

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

# ---------------------------------------------------------------------------
# MIDFLIGHT_ROOT-only path (no midflight on PATH, no adjacent hosts/scripts):
# skill run.sh must stage --provider into query.sh HOME config (query.sh has
# no -p flag). Same class of fix as Codex host_codex_circular_provider.
# ---------------------------------------------------------------------------
fake_root="$TEST_DIR/fake-midflight-root"
mkdir -p "$fake_root/scripts" "$TEST_DIR/skill-only/scripts"
cp "$SKILL_RUN" "$TEST_DIR/skill-only/scripts/run.sh"
chmod +x "$TEST_DIR/skill-only/scripts/run.sh"

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

export PATH="/usr/bin:/bin:$TEST_DIR/bin"
rm -f "$TEST_DIR/bin/midflight"
export MIDFLIGHT_ROOT="$fake_root"

out="$(bash "$TEST_DIR/skill-only/scripts/run.sh" --provider agy "$query" consult 2>/dev/null)"
assert_contains "$out" "provider=agy" "MIDFLIGHT_ROOT path must stage --provider into query HOME config"
assert_contains "$out" "ARGS:" "stub query.sh should receive positional args"

# Without --provider, query.sh sees the user's real config (not forced).
write_config <<'CFG'
provider=codex
CFG
out="$(bash "$TEST_DIR/skill-only/scripts/run.sh" "$query" consult 2>/dev/null)"
# No staging → stub still runs under real HOME from setup_test_env
assert_contains "$out" "provider=codex" "no --provider keeps user config provider"
assert_contains "$out" "ARGS:" "stub query.sh positional args without override"

# --provider without value should error clearly under set -u
set +e
err="$(bash "$TEST_DIR/skill-only/scripts/run.sh" --provider 2>&1)"
status=$?
set -e
assert_eq "2" "$status" "--provider without value exits 2"
assert_contains "$err" "--provider needs a value" "--provider missing value message"

# Also cover run-query.sh query-kind path: force MIDFLIGHT_ROOT without bin/
# so resolve-engine emits kind=query, and --provider still stages.
rm -f "$fake_root/bin/midflight" 2>/dev/null || true
mkdir -p "$fake_root/scripts"
# resolve needs check-config too for is_engine_root
: > "$fake_root/scripts/check-config.sh"
chmod +x "$fake_root/scripts/check-config.sh"
export PATH="/usr/bin:/bin"
export MIDFLIGHT_ROOT="$fake_root"
out="$(bash "$RUN" --provider oz --start-dir "$TEST_DIR" "$query" consult 2>/dev/null)"
assert_contains "$out" "provider=oz" "run-query query-kind stages --provider via HOME"

echo "PASS: host_grok_run_query"
