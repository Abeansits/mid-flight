# Grok Bot host adapter

Agent Skills for **Cursor's Grok Bot** that invoke the shared MidFlight engine.

**Important:** This is for **Cursor Grok Bot** assistants (sand-workflow skills), NOT xAI's Grok Build CLI. For Grok Build, see `hosts/grok/`.

| Skill | Invoke | Role |
|---|---|---|
| `skills/midflight` | `/midflight` | Consult / implement / video |
| `skills/midflight-check-config` | `/midflight-check-config` | Validate config + provider CLIs |

## Engine resolution

`scripts/resolve-engine.sh` (and the skill `scripts/run.sh` wrappers) pick an engine in this order:

1. `midflight` on `PATH`
2. `$MIDFLIGHT_ROOT` (checkout or install prefix)
3. Walk up from the skill path to a mid-flight repo root

When `$MIDFLIGHT_ROOT` is set and contains `bin/midflight`, that binary is preferred over falling straight to `scripts/query.sh`.

## Provider note

Grok Bot runs in Cursor's agent environment. There is **no** `provider=grok-bot` or `provider=cursor` yet, so circularity is not a concern. The default provider is often `codex`, which is a fine external consult from Grok Bot.

When a `cursor` provider is added later (ROADMAP waitlists `agent -p --mode=ask`), consider whether a circular guard is needed.

## Install doors

Install into Cursor's agent skill discovery paths so Grok Bot can find them:

```bash
# User-wide (syncs to Cloud Agents via Cursor Settings → Agents → Sync Skills)
mkdir -p ~/.cursor/skills
cp -R hosts/grok-bot/skills/midflight ~/.cursor/skills/midflight
cp -R hosts/grok-bot/skills/midflight-check-config ~/.cursor/skills/midflight-check-config
# or: ln -s "$(pwd)/hosts/grok-bot/skills/midflight" ~/.cursor/skills/midflight

# Project-local
mkdir -p .cursor/skills
ln -s "$(pwd)/hosts/grok-bot/skills/midflight" .cursor/skills/midflight
ln -s "$(pwd)/hosts/grok-bot/skills/midflight-check-config" .cursor/skills/midflight-check-config

# Also discovered: ~/.agents/skills/ and .agents/skills/
# (plus Claude/Codex compat dirs). Prefer ~/.cursor/skills/ for reliable /slash invoke.
mkdir -p ~/.agents/skills
ln -s "$(pwd)/hosts/grok-bot/skills/midflight" ~/.agents/skills/midflight
```

### Engine install

Engine must be reachable (`midflight` on `PATH` or `MIDFLIGHT_ROOT`):

```bash
# Quick install (puts midflight on PATH)
curl -fsSL https://raw.githubusercontent.com/Abeansits/mid-flight/main/scripts/install.sh | bash

# Or from a checkout:
./scripts/install.sh --from-dir . --prefix ~/.local
```

See the root [README](../../README.md) for the full install door.

## CI note

`tests/run_all.sh` shellcheck/find includes `hosts/` and runs `tests/host_*.sh`.
