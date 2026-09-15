# Grok Build host adapter

Agent Skills for [Grok Build](https://docs.x.ai/build/features/skills-plugins-marketplaces) that invoke the shared MidFlight engine.

| Skill | Invoke | Role |
|---|---|---|
| `skills/midflight` | `/midflight` | Consult / implement / video |
| `skills/midflight-check-config` | `/midflight-check-config` | Validate config + provider CLIs |

## Engine resolution

`scripts/resolve-engine.sh` (and the skill `scripts/run.sh` wrappers) pick an engine in this order:

1. `midflight` on `PATH`
2. `$MIDFLIGHT_ROOT` (checkout or install prefix)
3. Walk up from the skill path to a mid-flight repo root

## Provider note (no circular guard)

MidFlight has **no** `provider=grok` yet, so `host=Grok` + `provider=grok` circularity is N/A. The default provider is often `codex`, which is a fine external consult from Grok Build. When a `grok` provider is added later, reconsider a circular guard (similar to the Codex host).

## Install doors

Prefer a simple copy or symlink into Grok's skill discovery paths (no marketplace publish required):

```bash
# User-wide
mkdir -p ~/.grok/skills
cp -R hosts/grok/skills/midflight ~/.grok/skills/midflight
cp -R hosts/grok/skills/midflight-check-config ~/.grok/skills/midflight-check-config
# or: ln -s "$(pwd)/hosts/grok/skills/midflight" ~/.grok/skills/midflight

# Project-local (walked up to repo root)
mkdir -p .grok/skills
ln -s "$(pwd)/hosts/grok/skills/midflight" .grok/skills/midflight
ln -s "$(pwd)/hosts/grok/skills/midflight-check-config" .grok/skills/midflight-check-config

# Also discovered: ~/.agents/skills/ (Agents.md compatibility)
mkdir -p ~/.agents/skills
ln -s "$(pwd)/hosts/grok/skills/midflight" ~/.agents/skills/midflight
```

Engine still needs to be reachable (`midflight` on `PATH` or `MIDFLIGHT_ROOT`).

See the root [README](../../README.md#4-grok-build-skills) for the full install door.

## CI note

`tests/run_all.sh` shellcheck/find includes `hosts/` and runs `tests/host_*.sh`.
