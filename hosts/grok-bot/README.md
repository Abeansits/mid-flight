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

**Two paths:**

### A. Skills + engine on PATH (recommended for most users)

Install the standalone CLI, then copy skills:

```bash
# 1. Install engine to PATH
curl -fsSL https://raw.githubusercontent.com/Abeansits/mid-flight/main/scripts/install.sh | bash
midflight --version

# 2. Install provider CLI (e.g., Codex)
# See: https://github.com/openai/codex

# 3. Copy skills to Grok Bot / Cursor discovery path
mkdir -p ~/.cursor/skills
cp -R hosts/grok-bot/skills/midflight ~/.cursor/skills/midflight
cp -R hosts/grok-bot/skills/midflight-check-config ~/.cursor/skills/midflight-check-config
```

The skills will use `midflight` from PATH.

### B. Repo-local symlinks with MIDFLIGHT_ROOT (for development)

Keep the repo tree intact and symlink skills:

```bash
# 1. Clone the repo
git clone https://github.com/Abeansits/mid-flight.git
cd mid-flight

# 2. Install provider CLI (e.g., Codex)

# 3. Symlink skills into discovery path
mkdir -p ~/.cursor/skills
ln -s "$(pwd)/hosts/grok-bot/skills/midflight" ~/.cursor/skills/midflight
ln -s "$(pwd)/hosts/grok-bot/skills/midflight-check-config" ~/.cursor/skills/midflight-check-config

# 4. Optional: Set MIDFLIGHT_ROOT in your shell profile
export MIDFLIGHT_ROOT="$(pwd)"
```

The skills will walk up to find `hosts/grok-bot/scripts/` and the engine root.

### Alternative discovery paths

- `~/.agents/skills/` — cross-agent compatible
- `.cursor/skills/` — project-local
- `.agents/skills/` — project-local cross-agent

Prefer `~/.cursor/skills/` for reliable `/slash` invoke in Cursor Desktop / Grok Bot. Cloud Agent skill sync behavior may vary; verify skill availability in your Cloud Agent environment.

See the root [README](../../README.md) for full install options.

## CI note

`tests/run_all.sh` shellcheck/find includes `hosts/` and runs `tests/host_*.sh`.
