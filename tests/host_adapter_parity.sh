#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
source "$ROOT_DIR/tests/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

strip_line2() {
  awk 'NR != 2 { print }' "$1"
}

assert_same_ignoring_line2() {
  local file_a="$1"
  local file_b="$2"
  local label="$3"

  if ! diff -u <(strip_line2 "$file_a") <(strip_line2 "$file_b") >&2; then
    echo "FAIL: $label diverged between $file_a and $file_b" >&2
    exit 1
  fi
}

assert_same_exact() {
  local file_a="$1"
  local file_b="$2"
  local label="$3"

  if ! diff -u "$file_a" "$file_b" >&2; then
    echo "FAIL: $label diverged between $file_a and $file_b" >&2
    exit 1
  fi
}

# 1. Shared host adapter scripts must stay in lockstep across codex, cursor, and grok.
for host in cursor grok; do
  assert_same_ignoring_line2 \
    "$ROOT_DIR/hosts/codex/scripts/resolve-engine.sh" \
    "$ROOT_DIR/hosts/$host/scripts/resolve-engine.sh" \
    "resolve-engine.sh ($host vs codex)"

  assert_same_ignoring_line2 \
    "$ROOT_DIR/hosts/codex/scripts/run-check-config.sh" \
    "$ROOT_DIR/hosts/$host/scripts/run-check-config.sh" \
    "run-check-config.sh ($host vs codex)"

  assert_same_exact \
    "$ROOT_DIR/hosts/codex/skills/midflight-check-config/scripts/run.sh" \
    "$ROOT_DIR/hosts/$host/skills/midflight-check-config/scripts/run.sh" \
    "midflight-check-config/scripts/run.sh ($host vs codex)"
done

assert_same_exact \
  "$ROOT_DIR/hosts/codex/scripts/prefer-non-codex-provider.sh" \
  "$ROOT_DIR/hosts/codex/skills/midflight/scripts/prefer-non-codex-provider.sh" \
  "prefer-non-codex-provider.sh (host vs skill)"

assert_same_exact \
  "$ROOT_DIR/hosts/grok/scripts/prefer-non-grok-provider.sh" \
  "$ROOT_DIR/hosts/grok/skills/midflight/scripts/prefer-non-grok-provider.sh" \
  "prefer-non-grok-provider.sh (host vs skill)"

# 2. All hosts must preserve paths with spaces in run-check-config.sh and run-query.sh,
# and standalone copied skills must still resolve MIDFLIGHT_ROOT with spaces.
space_root="$TEST_DIR/midflight repo with spaces"
mkdir -p "$space_root/bin" "$space_root/scripts"

cat > "$space_root/bin/midflight" <<'STUB'
#!/bin/bash
printf 'SPACE_CLI:%s\n' "$*"
STUB
chmod +x "$space_root/bin/midflight"
: > "$space_root/scripts/query.sh"
cat > "$space_root/scripts/check-config.sh" <<'STUB'
#!/bin/bash
printf 'SPACE_CHECK_OK\n'
STUB
chmod +x "$space_root/scripts/query.sh" "$space_root/scripts/check-config.sh"

query="$(write_query_file <<'Q'
## Context
parity check
## Question
works with spaces?
Q
)"
write_config <<'CFG'
provider=oz
CFG

export PATH="/usr/bin:/bin"
export MIDFLIGHT_ROOT="$space_root"

for host in codex cursor grok; do
  check_out="$(bash "$ROOT_DIR/hosts/$host/scripts/run-check-config.sh" --start-dir "$TEST_DIR")"
  assert_eq "SPACE_CHECK_OK" "$check_out" "$host run-check-config.sh should handle MIDFLIGHT_ROOT with spaces"

  query_out="$(bash "$ROOT_DIR/hosts/$host/scripts/run-query.sh" --start-dir "$TEST_DIR" "$query" consult)"
  assert_contains "$query_out" "SPACE_CLI:" "$host run-query.sh should handle MIDFLIGHT_ROOT with spaces"

  no_start_dir_out="$(bash "$ROOT_DIR/hosts/$host/scripts/run-query.sh" "$query" consult)"
  assert_contains "$no_start_dir_out" "SPACE_CLI:" "$host run-query.sh should work without --start-dir under bash 3.2"

  # Simulate standalone skill install (copied outside repo tree, no adjacent hosts/*/scripts).
  isolated_skill="$TEST_DIR/isolated-$host/midflight"
  isolated_check="$TEST_DIR/isolated-$host/midflight-check-config"
  mkdir -p "$isolated_skill/scripts" "$isolated_check/scripts"
  cp "$ROOT_DIR/hosts/$host/skills/midflight/scripts/"*.sh "$isolated_skill/scripts/"
  cp "$ROOT_DIR/hosts/$host/skills/midflight-check-config/scripts/"*.sh "$isolated_check/scripts/"
  chmod +x "$isolated_skill/scripts/"*.sh "$isolated_check/scripts/"*.sh

  iso_check_out="$(bash "$isolated_check/scripts/run.sh")"
  assert_eq "SPACE_CHECK_OK" "$iso_check_out" "standalone $host check-config skill should resolve MIDFLIGHT_ROOT with spaces"

  iso_query_out="$(bash "$isolated_skill/scripts/run.sh" "$query" consult)"
  assert_contains "$iso_query_out" "SPACE_CLI:" "standalone $host midflight skill should resolve MIDFLIGHT_ROOT with spaces"
done

echo "PASS: host_adapter_parity"
