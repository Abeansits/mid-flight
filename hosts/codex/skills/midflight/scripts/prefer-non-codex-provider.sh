#!/usr/bin/env bash
# Codex-host circular-provider guard.
#
# When the MidFlight host is Codex and the configured/default provider is also
# codex, consulting Codex from Codex is usually a no-op second opinion.
# Prefer a different provider (agy → opencode → oz → gemini → grok → claude) unless the user
# explicitly opts in.
#
# Usage:
#   prefer-non-codex-provider.sh
#     Reads ~/.config/mid-flight/config (or MIDFLIGHT_CONFIG), prints the
#     provider MidFlight should use, and may warn on stderr.
#
# Exit codes:
#   0  — provider to use printed on stdout
#   1  — refused (circular with no alternative and no override)
#
# Override (any one):
#   MIDFLIGHT_ALLOW_CODEX_PROVIDER=1
#   --allow-codex-provider passed by the caller (exported as
#   MIDFLIGHT_ALLOW_CODEX_PROVIDER=1 before invoking this script)

set -euo pipefail

config_file="${MIDFLIGHT_CONFIG:-${HOME}/.config/mid-flight/config}"
provider="codex"

if [ -f "$config_file" ]; then
  value="$(grep '^provider=' "$config_file" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]' || true)"
  if [ -n "$value" ]; then
    provider="$value"
  fi
fi

if [ "$provider" = "antigravity" ]; then
  provider="agy"
fi

# Non-codex configured provider: leave it alone.
if [ "$provider" != "codex" ]; then
  printf '%s\n' "$provider"
  exit 0
fi

# Explicit override: allow circular Codex→Codex.
if [ "${MIDFLIGHT_ALLOW_CODEX_PROVIDER:-}" = "1" ]; then
  printf 'prefer-non-codex-provider: allowing provider=codex on Codex host (MIDFLIGHT_ALLOW_CODEX_PROVIDER=1)\n' >&2
  printf 'codex\n'
  exit 0
fi

pick=""
for candidate in agy opencode oz gemini grok claude; do
  if command -v "$candidate" >/dev/null 2>&1; then
    pick="$candidate"
    break
  fi
done

if [ -n "$pick" ]; then
  printf 'prefer-non-codex-provider: host=Codex and provider=codex would be circular; using %s instead.\n' "$pick" >&2
  printf 'prefer-non-codex-provider: set MIDFLIGHT_ALLOW_CODEX_PROVIDER=1 to force Codex anyway.\n' >&2
  printf '%s\n' "$pick"
  exit 0
fi

printf 'prefer-non-codex-provider: refused circular Codex→Codex consultation.\n' >&2
printf 'No alternate provider (agy, opencode, oz, gemini, grok, claude) found on PATH.\n' >&2
printf 'Install one of those CLIs, or set MIDFLIGHT_ALLOW_CODEX_PROVIDER=1 to override.\n' >&2
exit 1