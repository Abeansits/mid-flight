# MidFlight roadmap

Follow-up from the 2026-08-28 review. Highest leverage first. Do not collect CLIs for their own sake — each provider is a flag contract that will break (Codex `--full-auto` already did). OpenCode already multiplexes many *models*; add a CLI only when you want that **harness**.

## Done recently

### 1. Antigravity (`agy`) as the Google provider — shipped on `main` (v1.8.0)

- `provider=agy` (alias `antigravity` → binary `agy`)
- `provider=gemini` still calls `gemini` for enterprise / API-key users
- `agy -p --output-format text` plus optional `--model` / `--effort`
- Implement passes `--dangerously-skip-permissions`; consult/video do not
- Video prefers agy when on `PATH`, else Gemini; pinned `provider=gemini` stays on Gemini
- `agy_model` / `agy_effort` default empty so slugs don't rot

Still nice to have: a live `agy` run against a small local mp4. Stub tests cover `--add-dir` and no `@path`, not real multimodal.

### 2a. Codex host adapter — shipped on `main` (v1.9.0, PR #14)

Skills under `hosts/codex/skills/` (`$midflight`, `$midflight-check-config`), engine resolution (`PATH` → `MIDFLIGHT_ROOT` → repo walk-up), and a circular `host=Codex` + `provider=codex` guard that prefers `agy`/`opencode`/`oz`/`gemini`/`grok`/`claude` (override via `MIDFLIGHT_ALLOW_CODEX_PROVIDER=1`).

### 2b. Grok Build host adapter — shipped on `main` (v1.9.0, PR #15)

Skills under `hosts/grok/skills/` (`/midflight`, `/midflight-check-config`), same engine resolution as Codex. Circular `provider=grok` guard shipped with item 3. Default `provider=codex` remains a fine external consult from Grok. Install via copy/symlink into `~/.grok/skills/`, project `.grok/skills/`, or `~/.agents/skills/`.

### 2c. Cursor host adapter — shipped on `main` (v1.9.0, PR #16)

Skills under `hosts/cursor/skills/` (`/midflight`, `/midflight-check-config`), same engine resolution as Codex/Grok. **No** circular guard: `provider=cursor` does not exist yet (waitlisted `agent -p --mode=ask`), so default `provider=codex` is fine from Cursor. Install via copy/symlink into `~/.cursor/skills/`, project `.cursor/skills/`, or `~/.agents/skills/`; path-scoped `npx skills add Abeansits/mid-flight/hosts/cursor/skills --agent cursor` also works (plain repo install is ambiguous vs Codex/Grok skill names).

The planned host-adapter set (Claude `commands/` + Codex + Grok + Cursor) is complete. Standalone CLI Path (a) shipped in PR #7.

### 3. First-class provider harnesses — shipped on `main` (v1.10.0, PR #17)

Complementary *harnesses*, not “another model” (OpenCode can already route to many models):

- `grok -p` as a first-class provider (`provider=grok`, alias `grok-build`)
- Claude-as-provider (`claude -p` harness; `provider=claude`) — run the Claude Code CLI as an external consult from other hosts
- Grok host circular guard when `provider=grok` (prefer codex → agy → opencode → oz → gemini → claude; override via `MIDFLIGHT_ALLOW_GROK_PROVIDER=1`)
- Claude host documents that `provider=claude` is circular from Claude Code

Waitlist only: Cursor `agent -p --mode=ask`, GitHub Copilot `copilot -p`. Skip Aider / Amp / Crush unless someone asks.

### 4. Path (b) — CLI context without Claude — shipped on `main` (v1.11.0, PR #18)

`midflight --diff` / `--git-status` so the standalone CLI can build a Context section from the repo (capped at 100 KiB per section; override with `MIDFLIGHT_GIT_CONTEXT_MAX_BYTES`). Combinable with `--context` / `-i`. No auto `-i` defaults — include globs stay explicit.

### 5. Dual-consult — shipped on `main` (v1.12.0, PR #19)

Same question to two providers, print the disagreement. That is the actual product, not “we support 8 CLIs.”

- CLI: `midflight --dual agy "…"` (primary from config/`-p`) or `midflight --providers codex,agy "…"`
- Consult-only in v1 (refuse implement/video dual)
- Sequential runs; labeled Provider A / Provider B dump; light structural “where they differ” note (no LLM synthesis)
- If one provider fails, still show the successful answer + the error

### 6. Consult sandbox vs implement sandbox — this PR → v1.13.0

Codex consult (and other non-implement text modes) use `--sandbox read-only`; only implement keeps `workspace-write`.

Evidence that session/scratch still works under read-only: Codex CLI (`codex exec --help`, 0.154.0) documents `--sandbox` as the policy **for model-generated shell commands** only. Host session/rollout persistence is a separate path (`$CODEX_HOME`; `--ephemeral` opts out). Upstream issue openai/codex#42398 likewise states the flag “controls the worker’s tool execution.” The PR #9 deferral worry does not apply.

## Later

### 7. Real CLI install

`scripts/release.sh publish` already exists. Add a brew formula and/or `curl | bash` so people do not `ln -s` from a git clone. Version still lives in `.claude-plugin/plugin.json`; split that when the CLI is a real distribution.

## Out of scope unless asked

- Automatic background review / hook-based enforcement
- Replacing the user’s main agent
- Video as a headline feature (niche; currently tied to a dead consumer Gemini path)
