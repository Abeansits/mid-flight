#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

write_config <<'CFG'
provider=agy
CFG

write_agy_stub "agy-home-ok"

QUERY_FILE="$(
  write_query_file <<'Q'
## Question
Where does agy keep its sign-in?
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

# A real ~/.gemini is not rewritten. agy can use it directly.
mkdir -p "$HOME/.gemini"
output="$(run_query "$QUERY_FILE" consult)"
assert_eq "agy-home-ok" "$output" "consult should still return stubbed agy output"
assert_eq "" "$(cat "$TEST_DIR/agy_gemini_dir.txt")" \
  "a real ~/.gemini should leave --gemini_dir unset"
assert_eq "" "$(cat "$TEST_DIR/agy_unknown_args.txt")" \
  "consult agy has no read-only flag to pass"
assert_eq "no" "$(cat "$TEST_DIR/agy_skip_permissions.txt")" \
  "consult must not skip permissions"

# Temp homes symlink ~/.gemini. Point agy at the canonical directory.
rmdir "$HOME/.gemini"
real_gemini="$TEST_DIR/real gemini"
mkdir -p "$real_gemini"
canonical="$(cd "$real_gemini" && pwd -P)"
ln -s "$canonical" "$HOME/.gemini"
assert_real_dir "$canonical" "symlink target should be a real directory"

output="$(run_query "$QUERY_FILE" consult)"
assert_eq "$canonical" "$(cat "$TEST_DIR/agy_gemini_dir.txt")" \
  "a symlinked ~/.gemini should pass --gemini_dir set to the canonical directory"
assert_real_dir "$(cat "$TEST_DIR/agy_gemini_dir.txt")" \
  "--gemini_dir should be a real directory, not a symlink"
assert_eq "no" "$(cat "$TEST_DIR/agy_skip_permissions.txt")" \
  "consult must not skip permissions when --gemini_dir is set"

output="$(run_query "$QUERY_FILE" implement)"
assert_eq "agy-home-ok" "$output" "implement should still return stubbed agy output"
assert_eq "$canonical" "$(cat "$TEST_DIR/agy_gemini_dir.txt")" \
  "implement should also point --gemini_dir at the real directory"
assert_eq "yes" "$(cat "$TEST_DIR/agy_skip_permissions.txt")" \
  "implement must still pass --dangerously-skip-permissions"

# A dangling symlink is not a sign-in directory.
rm -f "$HOME/.gemini"
ln -s "$TEST_DIR/missing-gemini" "$HOME/.gemini"
output="$(run_query "$QUERY_FILE" consult)"
assert_eq "agy-home-ok" "$output" "a dangling ~/.gemini should still return stubbed agy output"
assert_eq "" "$(cat "$TEST_DIR/agy_gemini_dir.txt")" \
  "a dangling ~/.gemini symlink should leave --gemini_dir unset"

# -p builds the temp home that symlinks the real ~/.gemini.
rm -f "$HOME/.gemini"
mkdir -p "$HOME/.gemini"
canonical="$(cd "$HOME/.gemini" && pwd -P)"
output="$(run_cli -p agy --model gemini-4-hydrogen-high "Which home does the temp overlay use?")"
assert_eq "agy-home-ok" "$output" "-p agy should still return stubbed agy output"
assert_eq "gemini-4-hydrogen-high" "$(cat "$TEST_DIR/agy_model.txt")" \
  "-p --model should still reach agy"
assert_eq "$canonical" "$(cat "$TEST_DIR/agy_gemini_dir.txt")" \
  "a temp HOME from -p should pass the real ~/.gemini as --gemini_dir"
assert_real_dir "$(cat "$TEST_DIR/agy_gemini_dir.txt")" \
  "the -p --gemini_dir should be a real directory"
proc_home="$(cat "$TEST_DIR/agy_process_home.txt")"
if [ "$proc_home" = "$HOME" ]; then
  echo "FAIL: -p agy should still run under the temp home" >&2
  exit 1
fi
assert_eq "symlink" "$(cat "$TEST_DIR/agy_gemini_link.txt")" \
  "temp home ~/.gemini should be the overlay symlink the process sees"

# --model with provider=agy in config uses the same overlay.
output="$(run_cli --model gemini-4-hydrogen-high "Which home does --model use?")"
assert_eq "agy-home-ok" "$output" "--model with provider=agy should still return stubbed agy output"
assert_eq "gemini-4-hydrogen-high" "$(cat "$TEST_DIR/agy_model.txt")" \
  "--model should set agy_model from the staged config"
assert_eq "$canonical" "$(cat "$TEST_DIR/agy_gemini_dir.txt")" \
  "a temp HOME from --model should pass the real ~/.gemini as --gemini_dir"
assert_real_dir "$(cat "$TEST_DIR/agy_gemini_dir.txt")" \
  "the --model --gemini_dir should be a real directory"
if grep -q '^agy_model=' "$HOME/.config/mid-flight/config"; then
  echo "FAIL: --model wrote agy_model into the real config" >&2
  exit 1
fi
if grep -q '^provider=' "$HOME/.config/mid-flight/config" \
  && [ "$(grep '^provider=' "$HOME/.config/mid-flight/config")" != "provider=agy" ]; then
  echo "FAIL: -p changed provider in the real config" >&2
  exit 1
fi

echo "PASS: symlinked ~/.gemini passes --gemini_dir set to the real directory"
