#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_skill() {
  local skill_md="$1"
  local expected_name="$2"

  [ -f "$skill_md" ] || { echo "FAIL: missing $skill_md" >&2; exit 1; }

  local name desc
  name="$(awk 'BEGIN{f=0} /^---$/{f++; next} f==1 && /^name:/{sub(/^name:[[:space:]]*/,""); gsub(/"/,""); print; exit}' "$skill_md")"
  desc="$(awk 'BEGIN{f=0} /^---$/{f++; next} f==1 && /^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$skill_md")"

  if [ "$name" != "$expected_name" ]; then
    echo "FAIL: $skill_md name=$name expected=$expected_name" >&2
    exit 1
  fi
  if [ -z "$desc" ]; then
    echo "FAIL: $skill_md missing description" >&2
    exit 1
  fi
  if ! grep -q 'scripts/run.sh' "$skill_md"; then
    echo "FAIL: $skill_md should reference scripts/run.sh" >&2
    exit 1
  fi
}

assert_skill "$ROOT_DIR/hosts/grok/skills/midflight/SKILL.md" "midflight"
assert_skill "$ROOT_DIR/hosts/grok/skills/midflight-check-config/SKILL.md" "midflight-check-config"

grep -q 'provider=grok' "$ROOT_DIR/hosts/grok/skills/midflight/SKILL.md" \
  || { echo "FAIL: midflight skill should document provider=grok circularity" >&2; exit 1; }
grep -qi 'circular' "$ROOT_DIR/hosts/grok/skills/midflight/SKILL.md" \
  || { echo "FAIL: midflight skill should document circular guard" >&2; exit 1; }
grep -q 'MIDFLIGHT_ALLOW_GROK_PROVIDER' "$ROOT_DIR/hosts/grok/skills/midflight/SKILL.md" \
  || { echo "FAIL: midflight skill should document MIDFLIGHT_ALLOW_GROK_PROVIDER override" >&2; exit 1; }
grep -q '/midflight' "$ROOT_DIR/hosts/grok/skills/midflight/SKILL.md" \
  || { echo "FAIL: midflight skill should document /midflight slash invoke" >&2; exit 1; }

[ -f "$ROOT_DIR/hosts/grok/skills/midflight/scripts/run.sh" ]
[ -f "$ROOT_DIR/hosts/grok/skills/midflight/scripts/prefer-non-grok-provider.sh" ]
[ -f "$ROOT_DIR/hosts/grok/skills/midflight-check-config/scripts/run.sh" ]
[ -f "$ROOT_DIR/hosts/grok/scripts/resolve-engine.sh" ]
[ -f "$ROOT_DIR/hosts/grok/scripts/run-query.sh" ]
[ -f "$ROOT_DIR/hosts/grok/scripts/run-check-config.sh" ]
[ -f "$ROOT_DIR/hosts/grok/scripts/prefer-non-grok-provider.sh" ]

echo "PASS: host_grok_skill_frontmatter"
