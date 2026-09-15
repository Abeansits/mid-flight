#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
source "$ROOT_DIR/tests/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

RESOLVE="$ROOT_DIR/hosts/codex/scripts/resolve-engine.sh"

# From skill-like start dir inside the real repo tree → finds engine root
out="$(bash "$RESOLVE" --start-dir "$ROOT_DIR/hosts/codex/skills/midflight")"
kind="${out%% *}"
path="${out#* }"
assert_eq "cli" "$kind" "repo walk-up should prefer bin/midflight"
assert_eq "$ROOT_DIR/bin/midflight" "$path" "walk-up resolves bin/midflight"

out="$(bash "$RESOLVE" --check --start-dir "$ROOT_DIR/hosts/codex/skills/midflight")"
kind="${out%% *}"
path="${out#* }"
assert_eq "check" "$kind" "--check should emit check kind"
assert_eq "$ROOT_DIR/scripts/check-config.sh" "$path" "walk-up resolves check-config.sh"

# MIDFLIGHT_ROOT wins over a missing PATH midflight
export PATH="/usr/bin:/bin"
export MIDFLIGHT_ROOT="$ROOT_DIR"
out="$(bash "$RESOLVE")"
kind="${out%% *}"
path="${out#* }"
assert_eq "cli" "$kind" "MIDFLIGHT_ROOT should resolve cli"
assert_eq "$ROOT_DIR/bin/midflight" "$path" "MIDFLIGHT_ROOT bin/midflight"

# midflight on PATH is preferred
ln -s "$ROOT_DIR/bin/midflight" "$TEST_DIR/bin/midflight"
export PATH="$TEST_DIR/bin:/usr/bin:/bin"
unset MIDFLIGHT_ROOT
out="$(bash "$RESOLVE")"
kind="${out%% *}"
path="${out#* }"
assert_eq "cli" "$kind" "PATH midflight preferred"
assert_eq "$TEST_DIR/bin/midflight" "$path" "PATH midflight path"

# --check follows the on-PATH binary to its install root
out="$(bash "$RESOLVE" --check)"
kind="${out%% *}"
path="${out#* }"
assert_eq "check" "$kind" "PATH midflight --check"
assert_eq "$ROOT_DIR/scripts/check-config.sh" "$path" "follows symlink to check-config"

# Failure when nothing is available
export PATH="/usr/bin:/bin"
unset MIDFLIGHT_ROOT
set +e
err="$(bash "$RESOLVE" --start-dir "$TEST_DIR" 2>&1)"
status=$?
set -e
assert_eq "1" "$status" "missing engine should fail"
assert_contains "$err" "could not find MidFlight engine" "missing engine error message"

echo "PASS: host_codex_resolve_engine"
