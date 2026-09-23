#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/test_helpers.sh
source "$ROOT_DIR/tests/test_helpers.sh"

setup_test_env
trap cleanup_test_env EXIT

SKILL_DIR="$ROOT_DIR/hosts/grok-bot/skills"

# Check midflight skill frontmatter
MIDFLIGHT_SKILL="$SKILL_DIR/midflight/SKILL.md"
if [ ! -f "$MIDFLIGHT_SKILL" ]; then
  printf 'FAIL: midflight SKILL.md should exist\n' >&2
  exit 1
fi

frontmatter="$(sed -n '/^---$/,/^---$/p' "$MIDFLIGHT_SKILL")"
assert_contains "$frontmatter" "name: midflight" "should have name"
assert_contains "$frontmatter" "description:" "should have description"
assert_contains "$frontmatter" "metadata:" "should have metadata"

# Check that description mentions core capabilities
description="$(echo "$frontmatter" | grep 'description:' | cut -d'"' -f2)"
assert_contains "$description" "Codex" "description should mention Codex"
assert_contains "$description" "second opinion" "description should mention second opinion"

# Check midflight-check-config skill frontmatter
CHECK_CONFIG_SKILL="$SKILL_DIR/midflight-check-config/SKILL.md"
if [ ! -f "$CHECK_CONFIG_SKILL" ]; then
  printf 'FAIL: midflight-check-config SKILL.md should exist\n' >&2
  exit 1
fi

frontmatter="$(sed -n '/^---$/,/^---$/p' "$CHECK_CONFIG_SKILL")"
assert_contains "$frontmatter" "name: midflight-check-config" "should have correct name"
assert_contains "$frontmatter" "description:" "should have description"

# Check that skill scripts exist and are executable
if [ ! -f "$SKILL_DIR/midflight/scripts/run.sh" ]; then
  printf 'FAIL: midflight/scripts/run.sh should exist\n' >&2
  exit 1
fi

if [ ! -f "$SKILL_DIR/midflight-check-config/scripts/run.sh" ]; then
  printf 'FAIL: midflight-check-config/scripts/run.sh should exist\n' >&2
  exit 1
fi

# Verify scripts are executable
if [ ! -x "$SKILL_DIR/midflight/scripts/run.sh" ]; then
  printf 'FAIL: midflight/scripts/run.sh not executable\n' >&2
  exit 1
fi

if [ ! -x "$SKILL_DIR/midflight-check-config/scripts/run.sh" ]; then
  printf 'FAIL: midflight-check-config/scripts/run.sh not executable\n' >&2
  exit 1
fi

echo "PASS: host_grok_bot_skill_frontmatter"
