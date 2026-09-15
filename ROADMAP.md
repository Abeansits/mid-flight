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

Skills under `hosts/codex/skills/` (`$midflight`, `$midflight-check-config`), engine resolution (`PATH` → `MIDFLIGHT_ROOT` → repo walk-up), and a circular `host=Codex` + `provider=codex` guard that prefers `agy`/`opencode`/`oz`/`gemini` (override via `MIDFLIGHT_ALLOW_CODEX_PROVIDER=1`).

### 2b. Grok Build host adapter — this PR

Skills under `hosts/grok/skills/` (`/midflight`, `/midflight-check-config`), same engine resolution as Codex. **No** circular guard: `provider=grok` does not exist yet, so default `provider=codex` (or another configured CLI) is the intended external consult from Grok. Install via copy/symlink into `~/.grok/skills/`, project `.grok/skills/`, or `~/.agents/skills/`.

## Next

### 2c. Remaining host adapters

The product is “don’t leave the agent you’re in.” The engine is already host-agnostic.

Still to ship:

- Cursor

Standalone CLI Path (a) shipped in PR #7. Path (b) did not: the CLI does not auto-summarize working context.

### 3. First-class provider harnesses (after host adapters)

Complementary *harnesses*, not “another model” (OpenCode can already route to many models). Queue after host adapters:

- `grok -p` as a first-class provider
- Claude-as-provider (`claude -p` harness) — same class of work; run the Claude Code CLI as an external consult from other hosts

Waitlist only: Cursor `agent -p --mode=ask`, GitHub Copilot `copilot -p`. Skip Aider / Amp / Crush unless someone asks.

## Later

### 4. Path (b) — CLI context without Claude

`midflight --diff` / `--git-status` (and maybe `-i` defaults) so the standalone CLI can build a context section from the repo. This is what makes “not just a Claude plugin” true.

### 5. Dual-consult

Same question to two providers, print the disagreement. That is the actual product, not “we support 8 CLIs.”

### 6. Consult sandbox vs implement sandbox

Codex consult should be `--sandbox read-only`. Only implement needs `workspace-write`. Verify Codex still writes its own session/scratch state under read-only before switching — that is why it was deferred in PR #9.

### 7. Real CLI install

`scripts/release.sh publish` already exists. Add a brew formula and/or `curl | bash` so people do not `ln -s` from a git clone. Version still lives in `.claude-plugin/plugin.json`; split that when the CLI is a real distribution.

## Out of scope unless asked

- Automatic background review / hook-based enforcement
- Replacing the user’s main agent
- Video as a headline feature (niche; currently tied to a dead consumer Gemini path)
