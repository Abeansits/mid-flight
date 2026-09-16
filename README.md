# MidFlight

**Get a second opinion from another coding agent without leaving the one you're already in.**

You're mid-task. The approach feels right, but you want someone else to poke holes in it — or you want a precise change implemented by a different model. MidFlight sends a tight summary of the current work to Codex, OpenCode, Oz, Antigravity, Gemini, Grok, or Claude, then brings their answer back into your session.

No copy-paste. No rebuilding context. No switching tools.

```text
/midflight should we use SSE or WebSockets for real-time updates?
```

```text
Recommendation: Start with SSE.

Why:
- Updates are one-way server → client, so WebSockets add connection state you do not need yet.
- SSE fits the existing HTTP auth and proxy setup.
- Easier to debug, monitor, and roll back.

Watchouts:
- If you later need client-to-server events, revisit WebSockets.
- Confirm the load balancer handles long-lived HTTP responses.

Next step:
Ship SSE for notifications. Keep the event payload transport-agnostic so a WebSocket move stays cheap.
```

That outside take sits next to your current agent's analysis. You stay in the session and decide.

## Why this exists

Coding agents are strong, and they still get stuck in their own framing. MidFlight is the cheap way to get a *different* model to look at the same problem — while you still have all the context.

| You want | MidFlight does |
|---|---|
| A sanity check before you commit to an approach | **Consult** — advice only, no file changes |
| A precise, spec'd change done by another model | **Implement** — reads, edits, verifies |
| Eyes on a local file or YouTube URL | **Video** — Antigravity or Gemini multimodal analysis |

You don't pick the mode. MidFlight infers it from the question. Uncertain → consult (safe by default).

**Not for:** replacing your main agent, dumping a whole project with no scope, or background/hook-based review. If you can't name the question, don't invoke it.

## Install — five doors, same engine

You need `bash` and **one** provider CLI on your `PATH`, authenticated:

- [Codex CLI](https://github.com/openai/codex) (default)
- [OpenCode CLI](https://opencode.ai/docs/cli/)
- [Oz CLI](https://docs.warp.dev/reference/cli/cli)
- [Antigravity CLI](https://antigravity.google/docs/cli/install) (`agy`) — Google's current terminal agent
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) — enterprise / paid API key only (see [Gemini note](#gemini-cli-status))
- [Grok Build CLI](https://docs.x.ai/build/cli/reference) (`grok`)
- [Claude Code CLI](https://code.claude.com/docs/en/headless) (`claude`) — useful as a provider from non-Claude hosts

### 1. Claude Code plugin

```bash
claude plugin marketplace add Abeansits/mid-flight
claude plugin install mid-flight@mid-flight
```

Restart Claude Code, then:

```bash
/midflight should we use WebSockets or SSE for real-time updates?
/midflight                          # Claude picks the question from the session
/midflight-check-config             # validate provider setup
```

Claude already has the session, so it writes the context summary for you. It can also self-invoke after it is clearly stuck (multiple failed attempts, unfamiliar stack, two equally valid approaches) — and it says so when it does.

### 2. Standalone CLI

Same engine, no Claude Code required. Use it from a terminal, a script, or CI. You supply the question (and optionally the context).

```bash
ln -s "$(pwd)/bin/midflight" /usr/local/bin/midflight
midflight --version
```

```bash
midflight "should we use SSE or WebSockets for real-time updates?"
midflight -p agy "is this regex vulnerable to ReDoS?"
midflight --context notes.md --include "src/*.ts" "where is the leak?"
midflight -m implement -f request.md
midflight --video ./ad-v3.mp4 "does this match the storyboard?"
```

Full flag reference: [docs/standalone-usage.md](docs/standalone-usage.md).


### 3. Codex skills

Same engine, for [Codex](https://developers.openai.com/codex/skills) (`$midflight` instead of `/midflight`).

**Engine first** (the skills call it):

```bash
git clone https://github.com/Abeansits/mid-flight.git
cd mid-flight
ln -s "$(pwd)/bin/midflight" /usr/local/bin/midflight   # or set MIDFLIGHT_ROOT=$(pwd)
```

**Then install the skills** (pick one):

```bash
# User-wide via gh skill (Codex agent)
gh skill install Abeansits/mid-flight midflight --agent codex --scope user
gh skill install Abeansits/mid-flight midflight-check-config --agent codex --scope user

# Or via Codex $skill-installer from this repo:
#   hosts/codex/skills/midflight
#   hosts/codex/skills/midflight-check-config

# Or symlink from a checkout into ~/.agents/skills
mkdir -p ~/.agents/skills
ln -s "$(pwd)/hosts/codex/skills/midflight" ~/.agents/skills/midflight
ln -s "$(pwd)/hosts/codex/skills/midflight-check-config" ~/.agents/skills/midflight-check-config
```

Restart Codex (or let it pick up skills), then:

```text
$midflight should we use WebSockets or SSE for real-time updates?
$midflight                          # Codex picks the question from the session
$midflight-check-config             # validate provider setup
```

Because the host is Codex, MidFlight will **not** silently use `provider=codex` (circular). It prefers `agy` → `opencode` → `oz` → `gemini` → `grok` → `claude` on `PATH`, or refuses if none are available. Set `MIDFLIGHT_ALLOW_CODEX_PROVIDER=1` (or pass `--allow-codex-provider`) to force Codex anyway.

### 4. Grok Build skills

Same engine, for [Grok Build](https://docs.x.ai/build/features/skills-plugins-marketplaces) (`/midflight` slash skills).

**Engine first** (the skills call it):

```bash
git clone https://github.com/Abeansits/mid-flight.git
cd mid-flight
ln -s "$(pwd)/bin/midflight" /usr/local/bin/midflight   # or set MIDFLIGHT_ROOT=$(pwd)
```

**Then install the skills** (copy or symlink — prefer this over marketplace publish):

```bash
# User-wide (~/.grok/skills)
mkdir -p ~/.grok/skills
cp -R hosts/grok/skills/midflight ~/.grok/skills/midflight
cp -R hosts/grok/skills/midflight-check-config ~/.grok/skills/midflight-check-config
# or symlink:
# ln -s "$(pwd)/hosts/grok/skills/midflight" ~/.grok/skills/midflight

# Project-local (./.grok/skills, walked up to repo root)
mkdir -p .grok/skills
ln -s "$(pwd)/hosts/grok/skills/midflight" .grok/skills/midflight
ln -s "$(pwd)/hosts/grok/skills/midflight-check-config" .grok/skills/midflight-check-config

# Also discovered via Agents.md compatibility:
#   ~/.agents/skills/
```

Restart Grok Build (or open the extensions modal with `/skills`), then:

```text
/midflight should we use WebSockets or SSE for real-time updates?
/midflight                          # Grok picks the question from the session
/midflight-check-config             # validate provider setup
```

Because the host is Grok Build, MidFlight will **not** silently use `provider=grok` (circular). It prefers `codex` → `agy` → `opencode` → `oz` → `gemini` → `claude` on `PATH`, or refuses if none are available. Set `MIDFLIGHT_ALLOW_GROK_PROVIDER=1` (or pass `--allow-grok-provider`) to force Grok anyway. The default provider is often `codex`, which is already a fine external consult.


### 5. Cursor skills

Same engine, for [Cursor](https://cursor.com/docs/skills) (`/midflight` Agent Skills).

**Engine first** (the skills call it):

```bash
git clone https://github.com/Abeansits/mid-flight.git
cd mid-flight
ln -s "$(pwd)/bin/midflight" /usr/local/bin/midflight   # or set MIDFLIGHT_ROOT=$(pwd)
```

**Then install the skills** (copy or symlink — recommended):

```bash
# User-wide (~/.cursor/skills; can Sync Skills for Cloud Agents)
mkdir -p ~/.cursor/skills
cp -R hosts/cursor/skills/midflight ~/.cursor/skills/midflight
cp -R hosts/cursor/skills/midflight-check-config ~/.cursor/skills/midflight-check-config
# or symlink:
# ln -s "$(pwd)/hosts/cursor/skills/midflight" ~/.cursor/skills/midflight

# Project-local
mkdir -p .cursor/skills
ln -s "$(pwd)/hosts/cursor/skills/midflight" .cursor/skills/midflight
ln -s "$(pwd)/hosts/cursor/skills/midflight-check-config" .cursor/skills/midflight-check-config

# Also discovered: ~/.agents/skills/, .agents/skills/
# (plus Claude/Codex compat dirs). Prefer ~/.cursor/skills/ for reliable /slash invoke.
```

Optional via the [skills](https://github.com/vercel-labs/skills) CLI — **path-scope** so you do not pick up Codex/Grok copies of the same skill name:

```bash
npx skills add Abeansits/mid-flight/hosts/cursor/skills --agent cursor -g
```

Restart Cursor (or open a new Agent chat), then:

```text
/midflight should we use WebSockets or SSE for real-time updates?
/midflight                          # Cursor picks the question from the session
/midflight-check-config             # validate provider setup
```

There is **no** `provider=cursor` yet, so circular `host=Cursor` + `provider=cursor` does not apply. The default provider is often `codex`, which is a fine external consult from Cursor.

## Providers

| Provider | Consult | Implement | Video | Model | Extra |
|---|---|---|---|---|---|
| `codex` | Yes | Yes | No | `codex_model` | `codex_reasoning_effort` |
| `agy` | Yes | Yes | Yes | `agy_model` | `agy_effort` |
| `opencode` | Yes | Yes | No | `opencode_model` | `opencode_variant`, `opencode_format` |
| `oz` | Yes | Yes | No | `oz_model` | `oz_output_format`, `oz_profile` |
| `gemini` | Yes | Yes | Yes | `gemini_model` | — |
| `grok` | Yes | Yes | No | `grok_model` | `grok_effort` |
| `claude` | Yes | Yes | No | `claude_model` | — |

`provider=antigravity` is an alias for `agy`. `provider=grok-build` is an alias for `grok`.

From Claude Code, prefer a non-`claude` provider — `provider=claude` is circular on that host (same harness consulting itself).

Video uses your configured Google provider if it is `agy` or `gemini`. Otherwise it picks **agy if it's on `PATH`**, else Gemini.

### Gemini CLI status

On 18 June 2026, Google stopped serving **consumer** Gemini CLI requests (free, AI Pro, AI Ultra). Use `provider=agy` ([install](https://antigravity.google/docs/cli/install)). Keep `provider=gemini` only if you have an enterprise Code Assist license or a paid Gemini API key.

## Config

Create `~/.config/mid-flight/config` to override defaults:

```
provider=codex
codex_model=gpt-5.4
codex_reasoning_effort=high
agy_model=
agy_effort=
gemini_model=gemini-2.5-pro
opencode_model=
opencode_variant=high
opencode_format=default
oz_model=auto
oz_output_format=text
oz_profile=
grok_model=
grok_effort=
claude_model=
```

| Setting | Default | Description |
|---|---|---|
| `provider` | `codex` | `codex`, `agy`, `gemini`, `opencode`, `oz`, `grok`, or `claude` |
| `codex_model` | `gpt-5.4` | Codex model |
| `codex_reasoning_effort` | `high` | `low`, `medium`, `high` |
| `agy_model` | unset | Antigravity model slug (`agy models`); blank uses the CLI default |
| `agy_effort` | unset | `low`, `medium`, `high`; blank uses the CLI default |
| `gemini_model` | `gemini-2.5-pro` | Gemini model (enterprise / API-key path) |
| `opencode_model` | unset | Leave blank for the OpenCode CLI default |
| `opencode_variant` | `high` | e.g. `minimal`, `high`, `max` |
| `opencode_format` | `default` | `default` or `json` |
| `oz_model` | `auto` | `auto` is the general-purpose default; `auto-genius` for heavy consults |
| `oz_output_format` | `text` | Capture format |
| `oz_profile` | unset | Optional Oz agent profile |
| `grok_model` | unset | Grok model id; blank uses the CLI default |
| `grok_effort` | unset | `low`, `medium`, `high`; blank uses the CLI default |
| `claude_model` | unset | Claude model; blank uses the CLI default |

Config is independent of Claude Code (or any other host), so you can tune MidFlight without touching other tools.

## How it works

1. You (or the host agent) decide a second opinion would help.
2. A short **context + question** file is written — Claude does this from the session; the CLI uses what you pass (`--context`, `--include`, or a query file).
3. `scripts/query.sh` wraps that file with a mode prompt and calls the configured provider CLI.
4. The response comes back on stdout. The host agent presents it next to its own take.

No transcript parsing. No hooks. The current session already has the context; MidFlight just asks a focused question of a different model.

## Troubleshooting

Validate setup first: `/midflight-check-config` (Claude / Grok Build / Cursor), `$midflight-check-config` (Codex), or `bash scripts/check-config.sh` (CLI).

| Error | Cause | Fix |
|---|---|---|
| `'codex' CLI not found` | Codex not installed / not on `PATH` | [Install Codex](https://github.com/openai/codex) |
| `'agy' CLI not found` | Antigravity not installed / not on `PATH` | [Install agy](https://antigravity.google/docs/cli/install) |
| `'gemini' CLI not found` | Gemini not installed / not on `PATH` | Consumer access ended 18 Jun 2026 — [install agy](https://antigravity.google/docs/cli/install), or Gemini with an enterprise/API-key install |
| `'opencode' CLI not found` | OpenCode not installed / not on `PATH` | [Install OpenCode](https://opencode.ai/docs/cli/) |
| `'oz' CLI not found` | Oz not installed / not on `PATH` | [Install Oz](https://docs.warp.dev/reference/cli/cli) |
| `'grok' CLI not found` | Grok Build not installed / not on `PATH` | [Install Grok](https://docs.x.ai/build/cli/reference) |
| `'claude' CLI not found` | Claude Code CLI not installed / not on `PATH` | [Install Claude Code](https://code.claude.com/docs/en/headless) |
| `Codex query failed` | Auth or network | `codex --version`; check API key |
| `Codex query failed` with `unexpected argument '--flag'` | Installed Codex CLI dropped a flag MidFlight still passes | Upgrade MidFlight; this is a CLI contract mismatch, not auth |
| `Antigravity query failed` | Auth or provider error | `agy --version`; run `agy` once to sign in |
| `OpenCode query failed` | Auth or provider error | `opencode --help`; confirm credentials inside OpenCode |
| `Oz query failed` | Auth or provider error | `oz --help` or `oz whoami` |
| `Grok query failed` | Auth or provider error | `grok --version`; run `grok login` |
| `Claude query failed` | Auth or provider error | `claude --version`; confirm Claude Code login |
| `Empty response` | Provider returned nothing | Retry, or switch `provider=` in config |
| `MidFlight hangs before Codex responds` | Codex inherited an open stdin and is waiting for EOF | Upgrade MidFlight; stdin is now detached |
| `Video file exceeds 20MB limit` | Gemini inline-file limit | Compress or trim the video |
| `Could not determine file size` | `stat` failed on the video | Check path and permissions |

Debug logs: run the host with debug on (e.g. `claude --debug`). Lines are prefixed `[mid-flight]` on stderr (mode, provider, query size, response size, duration).

## Updating / uninstall (Claude plugin)

```bash
claude plugin marketplace update mid-flight
claude plugin update mid-flight@mid-flight
```

```bash
claude plugin remove mid-flight
claude plugin marketplace remove mid-flight
```

Restart Claude Code after either.

## Development

```bash
bash tests/run_all.sh
```

Follow-up work (agy provider, host adapters, CLI context): [ROADMAP.md](ROADMAP.md).

### Releasing

1. On a working branch: `scripts/release.sh prepare X.Y.Z` — bumps `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, commits.
2. Merge the PR, switch to a clean local `main` that matches `origin/main`, then `scripts/release.sh publish X.Y.Z`.

`publish` refuses unless local `main` is clean and up to date. Tag from `main`, not a feature branch.

<details>
<summary><strong>Architecture</strong></summary>

MidFlight is a thin router over other agents' CLIs.

- **Host** — Claude Code (`/midflight`), Codex (`$midflight` skills under `hosts/codex/skills/`), Grok Build (`/midflight` skills under `hosts/grok/skills/`), Cursor (`/midflight` skills under `hosts/cursor/skills/`), or the standalone `bin/midflight` CLI. The host is responsible for summarizing context.
- **Engine** — `scripts/query.sh` plus `scripts/lib/`. Assembles the prompt, picks the provider, captures the response.
- **Provider** — `codex`, `agy`, `gemini`, `opencode`, `oz`, `grok`, or `claude`. Isolated behind `query_<name>` in `scripts/lib/providers.sh`. Adding one is a new function, a router case, config keys, and tests.

Each invocation gets its own temp run workspace for staged inputs, prompt assembly, provider logs, and response capture. Stdin is detached before launching provider CLIs so a caller with an open pipe cannot deadlock Codex.

Video mode copies local files into a staging dir. Gemini gets `@path` plus `--include-directories`. Antigravity gets `--add-dir` and a plain path in the prompt (no `@path` syntax). URLs go in the prompt as-is. Gemini's 20MB inline-file limit is checked up front.

</details>

## License

MIT
