# Codex host adapter

Agent Skills for [Codex](https://developers.openai.com/codex/skills) that invoke the shared MidFlight engine.

| Skill | Invoke | Role |
|---|---|---|
| `skills/midflight` | `$midflight` | Consult / implement / video |
| `skills/midflight-check-config` | `$midflight-check-config` | Validate config + provider CLIs |

## Engine resolution

`scripts/resolve-engine.sh` (and the skill `scripts/run.sh` wrappers) pick an engine in this order:

1. `midflight` on `PATH`
2. `$MIDFLIGHT_ROOT` (checkout or install prefix)
3. Walk up from the skill path to a mid-flight repo root

## Circular provider guard

When this host is Codex and `provider=codex`, `scripts/prefer-non-codex-provider.sh` warns and prefers `agy` → `opencode` → `oz` → `gemini` → `grok` → `claude`. Override with `MIDFLIGHT_ALLOW_CODEX_PROVIDER=1` or `--allow-codex-provider`.

See the root [README](../../README.md#3-codex-skills) for install doors.

## CI note

`tests/run_all.sh` shellcheck/find includes `hosts/` and runs `tests/host_*.sh`. The workflow’s separate `bash -n` step still scans `scripts` + `tests` only until a follow-up with `workflow` scope widens it.
