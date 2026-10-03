#!/bin/bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

help_output="$(run_cli --help)"
assert_contains "$help_output" "Usage:" "--help should print usage"
assert_contains "$help_output" "--provider" "--help should list the provider flag"
assert_contains "$help_output" "--video" "--help should list the video flag"
assert_contains "$help_output" "--image-gen" "--help should list --image-gen"
assert_contains "$help_output" "--video-gen" "--help should list --video-gen"
assert_contains "$help_output" "--ref" "--help should list --ref"
assert_contains "$help_output" "--aspect" "--help should list --aspect"
assert_contains "$help_output" "720p" "--help should say video generation requests 720p"
assert_contains "$help_output" "opening frame" "--help should say the first reference is the opening frame"
assert_contains "$help_output" "--git-status" "--help should list --git-status"
assert_contains "$help_output" "--diff" "--help should list --diff"
assert_contains "$help_output" "--dual" "--help should list --dual"
assert_contains "$help_output" "--providers" "--help should list --providers"
assert_contains "$help_output" "Exit 0: provider reply on stdout" \
  "--help should state the success stream"
assert_contains "$help_output" "[mid-flight] logs on stderr" \
  "--help should put logs on stderr"
assert_contains "$help_output" "Exit 2: usage error" \
  "--help should state the usage exit"
assert_contains "$help_output" "midflight: … on stderr, empty stdout" \
  "--help should state the usage-error streams"
assert_contains "$help_output" "Exit 1: engine or provider error" \
  "--help should state the engine exit"
assert_contains "$help_output" "Error: … on stdout" \
  "--help should put Error: on stdout"
assert_contains "$help_output" "## Provider A: <name>" \
  "--help should name the dual Provider A heading"
assert_contains "$help_output" "## Provider B: <name>" \
  "--help should name the dual Provider B heading"
assert_contains "$help_output" "## Where they differ" \
  "--help should name the dual difference heading"
assert_contains "$help_output" "one absolute path" \
  "--help should state the media stdout shape"
assert_contains "$help_output" "-p on --image-gen must be codex or grok" \
  "--help should limit image-gen providers"
assert_contains "$help_output" "-p on --video-gen must be grok" \
  "--help should limit video-gen providers"
assert_contains "$help_output" "antigravity → agy" \
  "--help should list the antigravity alias"
assert_contains "$help_output" "grok-build → grok" \
  "--help should list the grok-build alias"
assert_contains "$help_output" "agy on PATH, else Gemini" \
  "--help should state video routing"
assert_contains "$help_output" "Stdin is ignored" \
  "--help should say stdin is ignored"
assert_contains "$help_output" "-- ends options" \
  "--help should say -- ends options"
assert_contains "$help_output" "docs/standalone-usage.md" \
  "--help should point at the standalone guide for sandbox details"
assert_contains "$help_output" "a readable PNG or JPEG that conflicts" \
  "--help should limit the aspect error to a readable frame"
assert_contains "$help_output" "with --aspect exits 2" \
  "--help should say a conflicting readable frame exits 2"
assert_contains "$help_output" "An unreadable frame warns" \
  "--help should say an unreadable frame warns"
assert_contains "$help_output" "on stderr and continues" \
  "--help should say an unreadable frame continues"
assert_contains "$help_output" "default off; dual ≈ 2N wall" \
  "--help should keep the short timeout contract"

if [[ "$help_output" == *"different shape is an error"* ]]; then
  echo "FAIL: --help still says a different opening-frame shape is always an error" >&2
  exit 1
fi
if [[ "$help_output" == *"no coreutils"* ]]; then
  echo "FAIL: --help still restates the watchdog implementation" >&2
  exit 1
fi

help_lines="$(printf '%s\n' "$help_output" | wc -l | tr -d '[:space:]')"
guide_lines="$(wc -l < "$ROOT_DIR/docs/standalone-usage.md" | tr -d '[:space:]')"
if [ "$help_lines" -ge "$guide_lines" ]; then
  echo "FAIL: --help (${help_lines} lines) must be shorter than docs/standalone-usage.md (${guide_lines} lines)" >&2
  exit 1
fi

short_help="$(run_cli -h)"
assert_eq "$help_output" "$short_help" "-h and --help should print the same help"

expected_version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$ROOT_DIR/.claude-plugin/plugin.json" | head -1)"

version_output="$(run_cli --version)"
assert_eq "midflight $expected_version" "$version_output" \
  "--version should report the plugin.json version"
assert_eq "$version_output" "$(run_cli -V)" "-V and --version should match"

echo "PASS: --help and --version produce real output"
