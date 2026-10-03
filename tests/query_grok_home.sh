#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

# The parent environment must not count as a pre-set GROK_HOME.
unset GROK_HOME || true

write_config <<'CFG'
provider=grok
CFG

write_grok_stub "grok-home-ok"

QUERY_FILE="$(
  write_query_file <<'Q'
## Question
Where does grok keep its home?
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

# A real ~/.grok is not rewritten. Grok can use it directly.
mkdir -p "$HOME/.grok"
output="$(run_query "$QUERY_FILE" consult)"
assert_eq "grok-home-ok" "$output" "consult should still return stubbed grok output"
assert_eq "" "$(cat "$TEST_DIR/grok_home.txt")" \
  "a real ~/.grok should leave GROK_HOME unset"
assert_eq "read-only" "$(cat "$TEST_DIR/grok_sandbox.txt")" \
  "consult must still pass --sandbox read-only"

# Temp homes symlink ~/.grok. Point grok at the canonical directory.
rmdir "$HOME/.grok"
real_grok="$TEST_DIR/real grok"
mkdir -p "$real_grok"
canonical="$(cd "$real_grok" && pwd -P)"
ln -s "$canonical" "$HOME/.grok"
assert_real_dir "$canonical" "symlink target should be a real directory"

output="$(run_query "$QUERY_FILE" consult)"
assert_eq "$canonical" "$(cat "$TEST_DIR/grok_home.txt")" \
  "unset GROK_HOME should be the canonical symlink target"
assert_real_dir "$(cat "$TEST_DIR/grok_home.txt")" \
  "GROK_HOME should be a real directory, not a symlink"
assert_eq "read-only" "$(cat "$TEST_DIR/grok_sandbox.txt")" \
  "consult must keep --sandbox read-only when GROK_HOME is rewritten"

for mode in implement image-gen video-gen; do
  output="$(run_query "$QUERY_FILE" "$mode")"
  assert_eq "grok-home-ok" "$output" "$mode should still return stubbed grok output"
  assert_eq "$canonical" "$(cat "$TEST_DIR/grok_home.txt")" \
    "$mode should also point GROK_HOME at the real directory"
  assert_eq "" "$(cat "$TEST_DIR/grok_sandbox.txt")" \
    "$mode must not pass --sandbox read-only"
  assert_eq "yes" "$(cat "$TEST_DIR/grok_always_approve.txt")" \
    "$mode must still pass --always-approve"
done

# A caller-supplied GROK_HOME wins, even when it is itself a symlink.
preset_dir="$TEST_DIR/preset grok"
mkdir -p "$preset_dir"
preset_link="$TEST_DIR/preset-link"
ln -s "$preset_dir" "$preset_link"
export GROK_HOME="$preset_link"
output="$(run_query "$QUERY_FILE" consult)"
assert_eq "$preset_link" "$(cat "$TEST_DIR/grok_home.txt")" \
  "a pre-set GROK_HOME must be forwarded unchanged"
assert_eq "read-only" "$(cat "$TEST_DIR/grok_sandbox.txt")" \
  "consult must still pass --sandbox read-only when GROK_HOME is pre-set"
unset GROK_HOME

# -p builds the temp home that symlinks the real ~/.grok. Same export.
rm -f "$HOME/.grok"
mkdir -p "$HOME/.grok"
canonical="$(cd "$HOME/.grok" && pwd -P)"
output="$(run_cli -p grok "Which home does the temp overlay use?")"
assert_eq "grok-home-ok" "$output" "-p grok should still return stubbed grok output"
assert_eq "$canonical" "$(cat "$TEST_DIR/grok_home.txt")" \
  "a temp HOME from -p should export the real ~/.grok"
assert_real_dir "$(cat "$TEST_DIR/grok_home.txt")" \
  "the -p GROK_HOME should be a real directory"
assert_eq "read-only" "$(cat "$TEST_DIR/grok_sandbox.txt")" \
  "consult via -p must still pass --sandbox read-only"
if [ -n "${GROK_HOME+x}" ]; then
  echo "FAIL: GROK_HOME leaked into the caller" >&2
  exit 1
fi

echo "PASS: symlinked ~/.grok sets GROK_HOME to the real directory"
