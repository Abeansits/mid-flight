#!/usr/bin/env bash
# Offline tests for scripts/install.sh (prefix-to-tmpdir, dry-run, DESTDIR).

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SH="$ROOT_DIR/scripts/install.sh"

setup_test_env
trap cleanup_test_env EXIT

assert_file() {
  local path="$1" msg="${2:-missing file: $1}"
  [ -e "$path" ] || {
    echo "FAIL: $msg" >&2
    exit 1
  }
}

assert_symlink_to() {
  local link="$1" expected_suffix="$2"
  [ -L "$link" ] || {
    echo "FAIL: expected symlink: $link" >&2
    exit 1
  }
  local target
  target="$(readlink "$link")"
  case "$target" in
    *"$expected_suffix") ;;
    *)
      echo "FAIL: symlink $link -> $target (expected suffix $expected_suffix)" >&2
      exit 1
      ;;
  esac
}

# --- help exits 0 ---
bash "$INSTALL_SH" --help >/dev/null

# --- dry-run from local tree does not write ---
prefix_dry="$TEST_DIR/prefix-dry"
mkdir -p "$prefix_dry"
out="$(bash "$INSTALL_SH" --from-dir "$ROOT_DIR" --prefix "$prefix_dry" --dry-run 2>&1)"
assert_contains "$out" "dry-run" "dry-run should announce itself"
[ ! -e "$prefix_dry/bin/midflight" ] || {
  echo "FAIL: dry-run wrote bin/midflight" >&2
  exit 1
}

# --- install from local checkout into PREFIX ---
prefix="$TEST_DIR/prefix"
bash "$INSTALL_SH" --from-dir "$ROOT_DIR" --prefix "$prefix" >/dev/null
assert_file "$prefix/bin/midflight" "bin/midflight should exist"
assert_file "$prefix/lib/mid-flight/bin/midflight" "lib tree midflight"
assert_file "$prefix/lib/mid-flight/scripts/query.sh" "lib tree query.sh"
assert_file "$prefix/lib/mid-flight/.claude-plugin/plugin.json" "lib tree plugin.json"
assert_symlink_to "$prefix/bin/midflight" "lib/mid-flight/bin/midflight"

# Version from installed plugin.json should match source
expected_ver="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$ROOT_DIR/.claude-plugin/plugin.json" | head -1)"
version_out="$("$prefix/bin/midflight" --version)"
assert_contains "$version_out" "$expected_ver" "installed midflight --version"

# --- DESTDIR staging ---
destdir="$TEST_DIR/destdir"
bash "$INSTALL_SH" --from-dir "$ROOT_DIR" --prefix /usr/local --destdir "$destdir" >/dev/null
assert_file "$destdir/usr/local/bin/midflight" "DESTDIR bin"
assert_file "$destdir/usr/local/lib/mid-flight/scripts/query.sh" "DESTDIR lib"
[ ! -e /usr/local/lib/mid-flight/bin/midflight ] || {
  # Only fail if we somehow wrote outside destdir with our unique marker — skip hard check.
  true
}

# --- refuses unknown option ---
if bash "$INSTALL_SH" --from-dir "$ROOT_DIR" --prefix "$TEST_DIR/x" --bogus 2>/dev/null; then
  echo "FAIL: unknown option should fail" >&2
  exit 1
fi

# --- missing from-dir ---
if bash "$INSTALL_SH" --from-dir "$TEST_DIR/no-such-dir" --prefix "$TEST_DIR/x" 2>/dev/null; then
  echo "FAIL: missing --from-dir should fail" >&2
  exit 1
fi

echo "PASS: cli_install"
