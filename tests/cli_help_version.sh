#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

help_output="$(run_cli --help)"
assert_contains "$help_output" "Usage:" "--help should print usage"
assert_contains "$help_output" "--provider" "--help should list the provider flag"
assert_contains "$help_output" "--video" "--help should list the video flag"

short_help="$(run_cli -h)"
assert_eq "$help_output" "$short_help" "-h and --help should print the same help"

expected_version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$ROOT_DIR/.claude-plugin/plugin.json" | head -1)"

version_output="$(run_cli --version)"
assert_eq "midflight $expected_version" "$version_output" \
  "--version should report the plugin.json version"
assert_eq "$version_output" "$(run_cli -V)" "-V and --version should match"

echo "PASS: --help and --version produce real output"
