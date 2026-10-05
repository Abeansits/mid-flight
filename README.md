# MidFlight

<p align="center">
  <img src="docs/logo.png" width="160" alt="MidFlight">
</p>

<p align="center">
  <a href="https://github.com/Abeansits/mid-flight/releases"><img alt="Release" src="https://img.shields.io/github/v/release/Abeansits/mid-flight?style=flat-square"></a>
  <a href="https://github.com/Abeansits/mid-flight/actions/workflows/shell-tests.yml"><img alt="Shell tests" src="https://img.shields.io/github/actions/workflow/status/Abeansits/mid-flight/shell-tests.yml?branch=main&style=flat-square"></a>
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/github/license/Abeansits/mid-flight?style=flat-square"></a>
</p>

```text
>be me
>three hours into the refactor
>agent says the design is sound
>agent also wrote the design
>conflict of interest detected
>think about opening a new chat
>paste half the repo in
>immediately forget which file was the bug
>scrap that plan
>/midflight
>a tight summary goes to Codex, OpenCode, Oz, Antigravity, Gemini, Grok, or Claude
>their answer comes back into the same session
>no copy-paste
>no second tab
>no "certainly, let me restate your question"
>mfw the other model finds the hole in four lines
>or you hand it one precise change and it just does that
>not "rewrite the app bestie"
>you still decide
>you just stopped letting the guy grade his own homework
```

## Usage example

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

## What you can do

| | What it does | Try |
|---|---|---|
| 🧠 | **Second opinion.** Another model answers. Codex and Grok block project writes. Other providers follow their own permission settings. | `midflight "SSE or WebSockets?"` |
| 🛠️ | **One precise change.** Hand it a spec. It edits that and stops. | `midflight -m implement -f request.md` |
| 👀 | **Two models, one question.** Both answers, side by side. | `midflight --dual agy "SSE or WebSockets?"` |
| 🎬 | **Watch a video.** A local file or a URL, via Antigravity or Gemini. | `midflight --video ./ad.mp4 "does this match the storyboard?"` |
| 🖼️ | **Make an image.** Grok or Codex. Prints the saved file path. | `midflight --image-gen "a paper plane over a fjord"` |
| 🎥 | **Make a video.** Grok only. Prints the saved file path. | `midflight --video-gen "the paper plane banks once and levels out"` |
| 📎 | **Bring the repo.** Notes, source files, branch, and diff ride along. | `midflight --git-status --diff "does this look right?"` |

Same engine from Claude Code, Codex, Grok Build, Cursor, or a plain terminal.

In a host session, `/midflight` picks consult, implement, or video from the question. Codex uses `$midflight`. If that is unclear, it stays a consult. Image generation, video generation, and a two-model consult are CLI flags.

**Not for:** replacing your main agent, dumping a whole project with no scope, or background/hook-based review. If you can't name the question, don't invoke it.

## Why this exists

Coding agents are strong, and they still get stuck in their own framing. MidFlight is the cheap way to get a *different* model to look at the same problem — while you still have all the context.

## Install — five doors, same engine

You need `bash` and **one** provider CLI on your `PATH`, authenticated:

- [Codex CLI](https://github.com/openai/codex) (default)
- [OpenCode CLI](https://opencode.ai/docs/cli/)
- [Oz CLI](https://docs.warp.dev/reference/cli/cli)
- [Antigravity CLI](https://antigravity.google/docs/cli/install) (`agy`) — Google's current terminal agent
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) — enterprise / paid API key only (see [Gemini note](#gemini-cli-status))
- [Grok Build CLI](https://docs.x.ai/build/cli/reference) (`grok`)
- [Claude Code CLI](https://code.claude.com/docs/en/headless) (`claude`) — useful as a provider from non-Claude hosts

<details>
<summary><strong>1. Claude Code plugin</strong></summary>

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

</details>

<details>
<summary><strong>2. Standalone CLI</strong></summary>

### 2. Standalone CLI

Same engine, no Claude Code required. Use it from a terminal, a script, or CI. You supply the question (and optionally the context).

**Homebrew (recommended).** `Formula/midflight.rb` lives in this repo. The repo is not named `homebrew-*`, so pass the git URL. The install uses the tagged release in the formula and puts `midflight` on your `PATH`.

```bash
brew tap Abeansits/mid-flight https://github.com/Abeansits/mid-flight
brew install Abeansits/mid-flight/midflight
midflight --version
```

`brew tap Abeansits/mid-flight` with no URL looks for `Abeansits/homebrew-mid-flight`, which does not exist. `brew install --formula ./Formula/midflight.rb` is not a tap, and current Homebrew rejects it.

To track `main` instead of the tagged release:

```bash
brew install --HEAD Abeansits/mid-flight/midflight
```

**Clone (no Homebrew).** From that checkout, `./bin/midflight` finds the engine next to itself. Host skills use the same checkout when `MIDFLIGHT_ROOT` points at it.

```bash
git clone https://github.com/Abeansits/mid-flight.git
cd mid-flight
./bin/midflight --version
export MIDFLIGHT_ROOT="$(pwd)"
```

**Already installed with `scripts/install.sh`.** Remove that copy so the shell does not run it instead of the Homebrew `midflight`. The old default directory was `/usr/local` when that directory was writable, otherwise `~/.local`.

```bash
rm -f ~/.local/bin/midflight /usr/local/bin/midflight
rm -rf ~/.local/lib/mid-flight /usr/local/lib/mid-flight
```

Then run the Homebrew commands above. If that copy lives in another directory, remove `bin/midflight` and `lib/mid-flight` there.

```bash
midflight "should we use SSE or WebSockets for real-time updates?"
midflight -p agy "is this regex vulnerable to ReDoS?"
midflight --dual agy "SSE or WebSockets?"
midflight --providers codex,agy "SSE or WebSockets?"
midflight --context notes.md --include "src/*.ts" "where is the leak?"
midflight --git-status --diff "does this change look right?"
midflight -m implement -f request.md
midflight --video ./ad-v3.mp4 "does this match the storyboard?"
midflight --image-gen "a paper plane over a fjord"
midflight --video-gen "the paper plane banks once and levels out"
```

Full flag reference: [docs/standalone-usage.md](docs/standalone-usage.md).

</details>

<details>
<summary><strong>3. Codex skills</strong></summary>

### 3. Codex skills

Same engine, for [Codex](https://developers.openai.com/codex/skills) (`$midflight` instead of `/midflight`).

**Engine first** (the skills call it):

```bash
brew tap Abeansits/mid-flight https://github.com/Abeansits/mid-flight
brew install Abeansits/mid-flight/midflight
# No Homebrew: clone the repo and export MIDFLIGHT_ROOT to that directory.
# See section 2.
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

</details>

<details>
<summary><strong>4. Grok Build skills</strong></summary>

### 4. Grok Build skills

Same engine, for [Grok Build](https://docs.x.ai/build/features/skills-plugins-marketplaces) (`/midflight` slash skills).

**Engine first** (the skills call it):

```bash
brew tap Abeansits/mid-flight https://github.com/Abeansits/mid-flight
brew install Abeansits/mid-flight/midflight
# No Homebrew: clone the repo and export MIDFLIGHT_ROOT to that directory.
# See section 2.
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

</details>

<details>
<summary><strong>5. Cursor skills</strong></summary>

### 5. Cursor skills

Same engine, for [Cursor](https://cursor.com/docs/skills) (`/midflight` Agent Skills). Cursor agents and Cursor's Grok Bot both load `~/.cursor/skills/`, so this is the adapter for both. xAI's Grok Build CLI is [§4](#4-grok-build-skills), not this one.

**Engine first** (the skills call it):

```bash
brew tap Abeansits/mid-flight https://github.com/Abeansits/mid-flight
brew install Abeansits/mid-flight/midflight
# No Homebrew: clone the repo and export MIDFLIGHT_ROOT to that directory.
# See section 2.
```

**Then install the skills** (copy or symlink — recommended):

```bash
# User-wide (~/.cursor/skills)
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

</details>

## Providers

| Provider | Consult | Implement | Video | Image | Model | Extra |
|---|---|---|---|---|---|---|
| `codex` | Yes | Yes | No | Yes | `codex_model` | `codex_reasoning_effort` |
| `agy` | Yes | Yes | Yes | No | `agy_model` | `agy_effort` |
| `opencode` | Yes | Yes | No | No | `opencode_model` | `opencode_variant`, `opencode_format` |
| `oz` | Yes | Yes | No | No | `oz_model` | `oz_output_format`, `oz_profile` |
| `gemini` | Yes | Yes | Yes | No | `gemini_model` | — |
| `grok` | Yes | Yes | No | Yes | `grok_model` | `grok_effort` |
| `claude` | Yes | Yes | No | No | `claude_model` | — |

`provider=antigravity` is an alias for `agy`. `provider=grok-build` is an alias for `grok`.

From Claude Code, prefer a non-`claude` provider — `provider=claude` is circular on that host (same harness consulting itself).

Video analysis uses your configured Google provider if it is `agy` or `gemini`. Otherwise it picks **agy if it's on `PATH`**, else Gemini.

Video generation (`--video-gen`) is Grok only. A `grok` config is kept. Any other config is overridden to Grok. `-p` must be `grok`. The prompt asks for 720p when `image_to_video` lists `resolution_name`. The saved file can be smaller. The first `--ref` is the opening frame and sets the shape. A readable PNG or JPEG that conflicts with `--aspect` exits 2. An unreadable frame warns on stderr and continues.

### Consult and file writes

`prompts/consult.md` tells the model not to edit files. That line is an instruction. MidFlight also passes a read-only flag when the provider CLI has one it can trust.

Codex consult passes `--sandbox read-only`. Implement and image generation pass `--sandbox workspace-write`. The sandbox covers model-generated shell and tool writes. Codex still writes session files under `$CODEX_HOME`. Video analysis does not select Codex. `query_codex` still passes `--sandbox read-only` for every mode except implement and image generation.

Grok consult passes `--sandbox read-only`. That profile still writes `~/.grok` and temp directories. An enterprise `requirements.toml` pin can override the CLI flag. Implement, image generation, and video generation pass `--always-approve` and leave the sandbox off so those modes can write.

Claude consult passes `--permission-mode plan`. Claude Code documents plan mode as reading and exploring without editing source. Shell commands can still run, and accepting a plan leaves plan mode. This is not a kernel sandbox. Implement passes `--dangerously-skip-permissions` and does not pass plan mode.

These consult paths do not get a read-only flag. Writes follow that CLI's own permission settings.

- Antigravity consult omits `--dangerously-skip-permissions`. Headless mode still auto-allows workspace file reads and writes. Commands, web, and files outside the workspace are soft-denied. Implement passes `--dangerously-skip-permissions`.
- Gemini consult passes no approval mode. `--approval-mode=plan` is documented as read-only, and headless plan mode switches to YOLO when the plan exits, so MidFlight does not pass it.
- OpenCode consult passes no permission flag. `edit` defaults to allow. `opencode run --auto` approves permissions that are not denied. `OPENCODE_PERMISSION` is merged with user config, so it is not a lock.
- Oz consult passes no permission flag. Writes follow the agent profile (`--profile` when `oz_profile` is set). The default CLI profile can read and write. `--share` shares the session. It does not sandbox the agent.

Video analysis runs on Antigravity or Gemini, so it has no read-only flag either.

Image generation uses your configured provider when it is `grok` or `codex`. Otherwise it picks **grok if it's on `PATH`**, else Codex if that CLI is on `PATH`, else Grok. `-p grok` and `-p codex` choose directly.

### Gemini CLI status

On 18 June 2026, Google stopped serving **consumer** Gemini CLI requests (free, AI Pro, AI Ultra). Use `provider=agy` ([install](https://antigravity.google/docs/cli/install)). Keep `provider=gemini` only if you have an enterprise Code Assist license or a paid Gemini API key.

## Config

Create `~/.config/mid-flight/config` to override defaults:

```
provider=codex
codex_model=gpt-6-sol
codex_reasoning_effort=high
agy_model=
agy_effort=
gemini_model=gemini-3.1-pro-preview
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
| `codex_model` | `gpt-6-sol` | Codex model |
| `codex_reasoning_effort` | `high` | `low`, `medium`, `high` |
| `agy_model` | unset | Antigravity model slug (`agy models`); blank uses the CLI default |
| `agy_effort` | unset | `low`, `medium`, `high`; blank uses the CLI default |
| `gemini_model` | `gemini-3.1-pro-preview` | Gemini Pro. Flash is `gemini-3.8-flash` |
| `opencode_model` | unset | Leave blank for the OpenCode CLI default |
| `opencode_variant` | `high` | e.g. `minimal`, `high`, `max`. On OpenCode v2+, appended as `#variant` only when `opencode_model` is set. A custom variant without a model is logged and skipped; the built-in `high` default is not |
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
2. A short **context + question** file is written — Claude does this from the session; the CLI uses what you pass (`--context`, `--include`, `--git-status`, `--diff`, or a query file).
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

## Updating / uninstall (Homebrew)

`brew upgrade` installs the tag in `Formula/midflight.rb` on `main`. A GitHub release is not a Homebrew upgrade until that file changes. The [Releasing](#releasing) steps include the checksum update.

```bash
brew update
brew upgrade Abeansits/mid-flight/midflight
```

```bash
brew uninstall Abeansits/mid-flight/midflight
```

`brew untap Abeansits/mid-flight` removes the tap. It leaves a Claude Code plugin install alone.

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

Shipped history and the current install note: [ROADMAP.md](ROADMAP.md).

### Releasing

1. On a working branch: `scripts/release.sh prepare X.Y.Z` — bumps `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, commits.
2. Merge the PR, switch to a clean local `main` that matches `origin/main`, then `scripts/release.sh publish X.Y.Z`. That publishes the git tag. It does not change Homebrew.
3. Update `Formula/midflight.rb` in a follow-up. Set `url` to `https://github.com/Abeansits/mid-flight/archive/refs/tags/vX.Y.Z.tar.gz` and set `sha256` to that file. Land that change on `main`.
4. Only then is the new tag a stable Homebrew install. `brew update`, then `brew upgrade Abeansits/mid-flight/midflight`.

```bash
curl -fsSL -o /tmp/midflight.tar.gz \
  https://github.com/Abeansits/mid-flight/archive/refs/tags/vX.Y.Z.tar.gz
sha256sum /tmp/midflight.tar.gz
```

On macOS, `shasum -a 256 /tmp/midflight.tar.gz` prints the same digest.

`publish` refuses unless local `main` is clean and up to date. Tag from `main`, not a feature branch.

`Formula/midflight.rb` currently installs `v1.18.0`. `brew upgrade` stays on that tag until the formula change for a newer tag is on `main`.

#### Release smoke check

Copy this after a release. The consult and the host skill need credentials on the maintainer's machine. They are not CI, and provider credentials do not go in GitHub Actions. A short note in the release PR or the release notes is enough evidence. Record the provider and the version you used.

```text
[ ] bash tests/run_all.sh
[ ] shell-tests CI green on ubuntu-latest and macos-latest
[ ] Maintainer, not CI: one real consult
    midflight -p <provider> "Reply with the single word pong."
    Answer is nonempty. Provider: ______. midflight --version: ______.
[ ] Maintainer, not CI: one installed host skill reaches the engine
    Host this release (rotate when that adapter changed): Claude / Codex / Grok / Cursor
    Invocation: /midflight or $midflight, with a small question. Reply came back.
[ ] After the formula change is on main:
    brew update
    brew upgrade Abeansits/mid-flight/midflight
    midflight --version
    midflight --help
```

A fresh machine can use `brew tap Abeansits/mid-flight https://github.com/Abeansits/mid-flight` and `brew install Abeansits/mid-flight/midflight` instead of `brew upgrade`. Do that only after the formula PR is on `main`. Until then, stable Homebrew is still the tag already in `Formula/midflight.rb`.

<details>
<summary><strong>Architecture</strong></summary>

MidFlight routes one question to another agent's CLI.

- **Host** — Claude Code (`/midflight`), Codex (`$midflight` skills under `hosts/codex/skills/`), Grok Build (`/midflight` skills under `hosts/grok/skills/`), Cursor and Cursor Grok Bot (`/midflight` skills under `hosts/cursor/skills/`), or the standalone `bin/midflight` CLI. The host is responsible for summarizing context.
- **Engine** — `scripts/query.sh` plus `scripts/lib/`. Assembles the prompt, picks the provider, captures the response.
- **Provider** — `codex`, `agy`, `gemini`, `opencode`, `oz`, `grok`, or `claude`. Isolated behind `query_<name>` in `scripts/lib/providers.sh`. Adding one is a new function, a router case, config keys, and tests.

Each invocation gets its own temp run workspace for staged inputs, prompt assembly, provider logs, and response capture. Stdin is detached before launching provider CLIs so a caller with an open pipe cannot deadlock Codex.

Consult write limits are per provider. Codex and Grok can block project writes. Claude consult uses plan mode. Antigravity, Gemini, OpenCode, and Oz follow their own permission settings. See [Consult and file writes](#consult-and-file-writes).

Video mode copies local files into a staging dir. Gemini gets `@path` plus `--include-directories`. Antigravity gets `--add-dir` and a plain path in the prompt (no `@path` syntax). URLs go in the prompt as-is. Gemini's 20MB inline-file limit is checked up front.

</details>

## License

MIT
