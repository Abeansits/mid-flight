# Cursor host adapter

Agent Skills for [Cursor](https://cursor.com/docs/skills) that invoke the shared MidFlight engine.

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

## Provider note (no circular guard)

MidFlight has **no** `provider=cursor` yet (ROADMAP waitlists `agent -p --mode=ask`), so `host=Cursor` + `provider=cursor` circularity is N/A. The default provider is often `codex`, which is a fine external consult from Cursor. When a `cursor` provider is added later, reconsider a circular guard (similar to the Codex host).

## Install doors

Prefer a simple copy or symlink into Cursor's skill discovery paths:

```bash
# User-wide (syncable for Cloud Agents via Cursor Settings → Agents → Sync Skills)
mkdir -p ~/.cursor/skills
cp -R hosts/cursor/skills/midflight ~/.cursor/skills/midflight
cp -R hosts/cursor/skills/midflight-check-config ~/.cursor/skills/midflight-check-config
# or: ln -s "$(pwd)/hosts/cursor/skills/midflight" ~/.cursor/skills/midflight

# Project-local
mkdir -p .cursor/skills
ln -s "$(pwd)/hosts/cursor/skills/midflight" .cursor/skills/midflight
ln -s "$(pwd)/hosts/cursor/skills/midflight-check-config" .cursor/skills/midflight-check-config

# Also discovered: ~/.agents/skills/ and .agents/skills/
# (and Claude/Codex compat dirs). Prefer ~/.cursor/skills/ for reliable /slash invoke.
mkdir -p ~/.agents/skills
ln -s "$(pwd)/hosts/cursor/skills/midflight" ~/.agents/skills/midflight
```

### Optional: `npx skills` CLI

The [skills](https://github.com/vercel-labs/skills) CLI discovers every `SKILL.md` in the repo. Plain:

```bash
npx skills add Abeansits/mid-flight --skill midflight --agent cursor
```

is **ambiguous** because `hosts/codex/` and `hosts/grok/` also ship skills named `midflight`. Scope the path so Cursor gets this adapter:

```bash
npx skills add Abeansits/mid-flight/hosts/cursor/skills --agent cursor -g
# or one skill:
npx skills add Abeansits/mid-flight/hosts/cursor/skills --skill midflight --agent cursor -g
```

If the CLI lands skills under `~/.agents/skills/` only, symlink into `~/.cursor/skills/` so `/midflight` slash invoke works.

Engine still needs to be reachable (`midflight` on `PATH` or `MIDFLIGHT_ROOT`).

See the root [README](../../README.md#5-cursor-skills) for the full install door.

## CI note

`tests/run_all.sh` shellcheck/find includes `hosts/` and runs `tests/host_*.sh`.
