#!/usr/bin/env bash
# Grok Build host circular-provider guard.
#
# When the MidFlight host is Grok Build and the configured provider is also
# grok (or alias grok-build), consulting Grok from Grok is usually a no-op
# second opinion. Prefer a different provider
# (codex → agy → opencode → oz → gemini → claude) unless the user explicitly
# opts in.
#
# Usage:
#   prefer-non-grok-provider.sh
#     Reads ~/.config/mid-flight/config (or MIDFLIGHT_CONFIG), prints the
#     provider MidFlight should use, and may warn on stderr.
#
# Exit codes:
#   0  — provider to use printed on stdout
#   1  — refused (circular with no alternative and no override)
#
# Override (any one):
#   MIDFLIGHT_ALLOW_GROK_PROVIDER=1
#   --allow-grok-provider passed by the caller (exported as
#   MIDFLIGHT_ALLOW_GROK_PROVIDER=1 before invoking this script)

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
if [ "$provider" = "grok-build" ]; then
  provider="grok"
fi

# Non-grok configured provider: leave it alone.
if [ "$provider" != "grok" ]; then
  printf '%s\n' "$provider"
  exit 0
fi

# Explicit override: allow circular Grok→Grok.
if [ "${MIDFLIGHT_ALLOW_GROK_PROVIDER:-}" = "1" ]; then
  printf 'prefer-non-grok-provider: allowing provider=grok on Grok host (MIDFLIGHT_ALLOW_GROK_PROVIDER=1)\n' >&2
  printf 'grok\n'
  exit 0
fi

pick=""
for candidate in codex agy opencode oz gemini claude; do
  if command -v "$candidate" >/dev/null 2>&1; then
    pick="$candidate"
    break
  fi
done

if [ -n "$pick" ]; then
  printf 'prefer-non-grok-provider: host=Grok and provider=grok would be circular; using %s instead.\n' "$pick" >&2
  printf 'prefer-non-grok-provider: set MIDFLIGHT_ALLOW_GROK_PROVIDER=1 to force Grok anyway.\n' >&2
  printf '%s\n' "$pick"
  exit 0
fi

printf 'prefer-non-grok-provider: refused circular Grok→Grok consultation.\n' >&2
printf 'No alternate provider (codex, agy, opencode, oz, gemini, claude) found on PATH.\n' >&2
printf 'Install one of those CLIs, or set MIDFLIGHT_ALLOW_GROK_PROVIDER=1 to override.\n' >&2
exit 1
