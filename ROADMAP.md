# MidFlight roadmap

Follow-up from the 2026-08-28 review. Highest leverage first. Do not collect CLIs for their own sake — each provider is a flag contract that will break (Codex `--full-auto` already did). OpenCode already multiplexes many *models*; add a CLI only when you want that **harness**.

## Now

### 1. Antigravity (`agy`) as the Google provider

Consumer Gemini CLI stopped serving requests on 18 Jun 2026 (free / AI Pro / AI Ultra). Enterprise Code Assist and paid Gemini API keys still work.

- Canonical config: `provider=agy` (alias `antigravity` → binary `agy`)
- Keep `provider=gemini` calling the `gemini` binary for enterprise / API-key users
- Headless shape: `agy -p "..." --output-format text` plus optional `--model`, `--effort`
- Implement mode needs `--dangerously-skip-permissions` (headless otherwise soft-denies writes)
- Consult should **not** skip permissions
- Video is the risky bit: Gemini uses `@path` + `--include-directories`. Agy uses `--add-dir` and does not document the `@path` inline syntax. Prefer `agy` for video when it is on `PATH`, else `gemini`. Probe real `agy` against a small local mp4 before claiming video.
- Default `agy_model` should be empty (agy slugs rotate). Do not pin a rotting Gemini 2.5 default onto agy.

Install: https://antigravity.google/docs/cli/install (`curl -fsSL https://antigravity.google/cli/install.sh | bash`). Docs: https://antigravity.google/docs/cli/headless/

## Next

### 2. Host adapters (more important than more providers)

The product is “don’t leave the agent you’re in.” The engine is already host-agnostic. `/midflight` only exists as a Claude Code command.

Ship the same skill/plugin for:

- Grok Build
- Cursor
- Codex

Standalone CLI Path (a) shipped in PR #7. Path (b) did not: the CLI does not auto-summarize working context.

### 3. `grok -p` as a first-class provider

Complementary *harness*, not “another Grok model” (OpenCode can already route to Grok-the-model). Do this after agy.

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
