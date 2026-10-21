#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

# The parent environment must not count as a pre-set CODEX_HOME.
unset CODEX_HOME || true

write_config <<'CFG'
provider=codex
codex_model=test-model
codex_reasoning_effort=high
CFG

write_codex_stub "codex-home-ok"

QUERY_FILE="$(
  write_query_file <<'Q'
## Question
Where does codex keep its home?
Q
)"

assert_real_dir() {
  local path="$1"
  local message="$2"

  if [ ! -d "$path" ] || [ -L "$path" ]; then
    echo "FAIL: $message" >&2
    echo "Path: $path" >&2
    exit 1
  fi
}

# A real ~/.codex is not rewritten. Codex can use it directly.
mkdir -p "$HOME/.codex"
output="$(run_query "$QUERY_FILE" consult)"
assert_eq "codex-home-ok" "$output" "consult should still return stubbed codex output"
assert_eq "" "$(cat "$TEST_DIR/codex_home.txt")" \
  "a real ~/.codex should leave CODEX_HOME unset"
assert_eq "read-only" "$(cat "$TEST_DIR/codex_sandbox.txt")" \
  "consult must still pass --sandbox read-only"

# Temp homes symlink ~/.codex. Point codex at the canonical directory.
rmdir "$HOME/.codex"
real_codex="$TEST_DIR/real codex"
mkdir -p "$real_codex"
canonical="$(cd "$real_codex" && pwd -P)"
ln -s "$canonical" "$HOME/.codex"
assert_real_dir "$canonical" "symlink target should be a real directory"

output="$(run_query "$QUERY_FILE" consult)"
assert_eq "$canonical" "$(cat "$TEST_DIR/codex_home.txt")" \
  "unset CODEX_HOME should be the canonical symlink target"
assert_real_dir "$(cat "$TEST_DIR/codex_home.txt")" \
  "CODEX_HOME should be a real directory, not a symlink"
assert_eq "read-only" "$(cat "$TEST_DIR/codex_sandbox.txt")" \
  "consult must keep --sandbox read-only when CODEX_HOME is rewritten"

for mode in implement image-gen; do
  output="$(run_query "$QUERY_FILE" "$mode")"
  assert_eq "codex-home-ok" "$output" "$mode should still return stubbed codex output"
  assert_eq "$canonical" "$(cat "$TEST_DIR/codex_home.txt")" \
    "$mode should also point CODEX_HOME at the real directory"
  assert_eq "workspace-write" "$(cat "$TEST_DIR/codex_sandbox.txt")" \
    "$mode must still pass --sandbox workspace-write"
done

# A caller-supplied CODEX_HOME wins, even when it is itself a symlink.
preset_dir="$TEST_DIR/preset codex"
mkdir -p "$preset_dir"
preset_link="$TEST_DIR/preset-link"
ln -s "$preset_dir" "$preset_link"
export CODEX_HOME="$preset_link"
output="$(run_query "$QUERY_FILE" consult)"
assert_eq "$preset_link" "$(cat "$TEST_DIR/codex_home.txt")" \
  "a pre-set CODEX_HOME must be forwarded unchanged"
assert_eq "read-only" "$(cat "$TEST_DIR/codex_sandbox.txt")" \
  "consult must still pass --sandbox read-only when CODEX_HOME is pre-set"
unset CODEX_HOME

# An empty CODEX_HOME is set, so the symlink is not rewritten over it.
export CODEX_HOME=""
output="$(run_query "$QUERY_FILE" consult)"
assert_eq "" "$(cat "$TEST_DIR/codex_home.txt")" \
  "an empty CODEX_HOME must be left empty"
assert_eq "read-only" "$(cat "$TEST_DIR/codex_sandbox.txt")" \
  "consult must still pass --sandbox read-only when CODEX_HOME is empty"
unset CODEX_HOME

# A dangling symlink is not a usable home. The consult still runs.
rm -f "$HOME/.codex"
ln -s "$TEST_DIR/missing codex" "$HOME/.codex"
output="$(run_query "$QUERY_FILE" consult)"
assert_eq "codex-home-ok" "$output" "a dangling ~/.codex symlink should still return output"
assert_eq "" "$(cat "$TEST_DIR/codex_home.txt")" \
  "a dangling ~/.codex symlink should leave CODEX_HOME unset"
assert_eq "read-only" "$(cat "$TEST_DIR/codex_sandbox.txt")" \
  "consult must still pass --sandbox read-only when ~/.codex is dangling"

# -p builds the temp home that symlinks the real ~/.codex. Same export.
rm -f "$HOME/.codex"
mkdir -p "$HOME/.codex"
canonical="$(cd "$HOME/.codex" && pwd -P)"
output="$(run_cli -p codex "Which home does the temp overlay use?")"
assert_eq "codex-home-ok" "$output" "-p codex should still return stubbed codex output"
assert_eq "$canonical" "$(cat "$TEST_DIR/codex_home.txt")" \
  "a temp HOME from -p should export the real ~/.codex"
assert_real_dir "$(cat "$TEST_DIR/codex_home.txt")" \
  "the -p CODEX_HOME should be a real directory"
assert_eq "read-only" "$(cat "$TEST_DIR/codex_sandbox.txt")" \
  "consult via -p must still pass --sandbox read-only"
if [ -n "${CODEX_HOME+x}" ]; then
  echo "FAIL: CODEX_HOME leaked into the caller" >&2
  exit 1
fi

echo "PASS: symlinked ~/.codex sets CODEX_HOME to the real directory"
