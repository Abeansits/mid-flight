# mid-flight

```text
 __  __ ___ ____        _____ _     ___ ____ _   _ _____
|  \/  |_ _|  _ \ _____|  ___| |   |_ _/ ___| | | |_   _|
| |\/| || || | | |_____| |_  | |    | | |  _| |_| | | |
| |  | || || |_| |     |  _| | |___ | | |_| |  _  | | |
|_|  |_|___|____/      |_|   |_____|___\____|_| |_| |_|
```

**Get a second opinion through Codex, Gemini, OpenCode, or Oz without leaving your Claude Code session.**

MidFlight is a [Claude Code](https://claude.ai/code) plugin for moments when you're already in the middle of a task and want outside signal before you continue.

Instead of copying context into another tool by hand, you run `/midflight`, Claude summarizes the relevant state, and the external model responds with focused advice, precise implementation help, or video analysis.

At a glance:

- Ask architecture, debugging, and tradeoff questions without leaving Claude Code
- Hand off tightly scoped implementation work to an external model
- Analyze local or remote videos with Gemini's multimodal support
- Let Claude self-invoke when it recognizes it would benefit from another perspective

## What it's for

- Sanity-checking an approach when you're unsure between a few valid options
- Getting unstuck on debugging, architecture, or API integration work
- Delegating a precise, well-scoped implementation task
- Reviewing creative assets or ads through structured video analysis
- Adding outside signal without rebuilding all of the context manually

## What it's not for

- Replacing Claude Code as your main development loop
- Handing off an entire project with no clear scope or constraints
- Automatic background review or hook-based workflow enforcement
- Vague "go build this whole thing" requests with no concrete target
- General-purpose browsing or research unrelated to the task already in progress

## How it works

1. You're mid-development and want a second opinion
2. Run `/midflight should we use WebSockets or SSE here?` (or just `/midflight` and Claude figures out what to ask)
3. Claude summarizes the current context and question
4. The query is sent to your configured provider (Codex, Gemini, OpenCode, or Oz)
5. Claude presents the external model's perspective alongside its own analysis

No transcript parsing, no hooks — Claude already has full context, so it writes a concise summary and question directly.

## Example output

Here's the kind of consult response MidFlight is meant to surface:

```text
Recommendation: Start with SSE.

Why:
- Your updates are one-way from server to client, so WebSockets adds connection and state complexity you do not need yet.
- SSE fits cleanly with your existing HTTP auth and proxy setup.
- It will be easier to debug, monitor, and roll back if needed.

Watchouts:
- If you later need client-to-server realtime events, revisit WebSockets.
- Confirm your load balancer and hosting platform handle long-lived HTTP responses well.

Suggested next step:
Implement SSE for notifications now, and keep the event payload contract transport-agnostic so a WebSocket move stays cheap later.
```

Claude will usually present that outside perspective alongside its own recommendation, so you get a second opinion without losing the flow of the session.

## Modes

MidFlight automatically infers the right mode from your query:

- **Consult** (default) — "Should we use X or Y?", debugging help, architecture validation. The external model provides advice without modifying files.
- **Implement** — Precise, spec-driven changes: "Add method X to file Y with these exact signatures." The external model reads files, makes edits, and runs verification.
- **Video** — Analyze video files or URLs using Gemini's multimodal capabilities. Produces structured scene breakdowns, ad quality reviews, and content verification. Auto-switches to Gemini regardless of your configured provider.

You don't need to specify which mode — Claude classifies intent from the query. When uncertain, it defaults to consult (safe by default).

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- One of the following providers:
  - [Codex CLI](https://github.com/openai/codex) installed and authenticated (default)
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli) installed and authenticated
  - [OpenCode CLI](https://opencode.ai/docs/cli/) installed and authenticated
  - [Oz CLI](https://docs.warp.dev/reference/cli/cli) installed and authenticated
- `bash` in your PATH

## Provider capability map

This is the current provider matrix for MidFlight.

| Provider | Status | Consult | Implement | Video | Model selection | Extra tuning |
|----------|--------|---------|-----------|-------|-----------------|--------------|
| `codex` | Shipped | Yes | Yes | No | `codex_model` | `codex_reasoning_effort` |
| `gemini` | Shipped | Yes | Yes | Yes | `gemini_model` | None today |
| `opencode` | Shipped | Yes | Yes | No | `opencode_model` | `opencode_variant`, `opencode_format` |
| `oz` | Shipped | Yes | Yes | No | `oz_model` | `oz_output_format`, `oz_profile` |

Video mode remains Gemini-only today because MidFlight relies on Gemini's current multimodal path for local files and URLs.

## Install

```bash
claude plugin marketplace add Abeansits/mid-flight
claude plugin install mid-flight@mid-flight
```

Restart Claude Code after installing.

## Releasing

MidFlight releases work best as a two-step flow:

1. Run `scripts/release.sh prepare X.Y.Z` on your working branch. This bumps
   `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, then
   creates a release-version commit for the PR.
2. Merge that PR, switch to local `main`, and run
   `scripts/release.sh publish X.Y.Z`.

`publish` intentionally refuses to run unless local `main` is clean and fully
up to date with `origin/main`. Tag from a clean `main`, not from a feature
branch or a dirty checkout.

## Config

Create `~/.config/mid-flight/config` to override defaults:

```
provider=codex
codex_model=gpt-5.4
codex_reasoning_effort=high
gemini_model=gemini-2.5-pro
opencode_model=
opencode_variant=high
opencode_format=default
oz_model=auto
oz_output_format=text
oz_profile=
```

| Setting                  | Default          | Description |
|--------------------------|------------------|-------------|
| `provider`               | `codex`          | Query provider (`codex`, `gemini`, `opencode`, or `oz`) |
| `codex_model`            | `gpt-5.4`        | Codex model to use |
| `codex_reasoning_effort` | `high`           | Codex reasoning effort (`low`, `medium`, `high`) |
| `gemini_model`           | `gemini-2.5-pro` | Gemini model to use |
| `opencode_model`         | unset            | OpenCode model to use; leave blank to use the CLI default |
| `opencode_variant`       | `high`           | OpenCode reasoning variant such as `minimal`, `high`, or `max` |
| `opencode_format`        | `default`        | OpenCode output format (`default` or `json`) |
| `oz_model`               | `auto`           | Oz model or preset to use; `auto` is the recommended general-purpose default |
| `oz_output_format`       | `text`           | Oz output format used for capture |
| `oz_profile`             | unset            | Optional Oz agent profile |

Keeping MidFlight's config separate makes it easy to tune these settings without affecting other Claude Code helpers.

For Oz specifically, `auto` is a good default for general MidFlight use. If you mainly use MidFlight for deep debugging, architecture tradeoffs, or other reasoning-heavy consults, try `auto-genius`.

## Usage

```bash
# Ask a specific question
/midflight should we use WebSockets or SSE for real-time updates?

# No question — Claude identifies what needs a second opinion
/midflight

# Analyze a local video file
/midflight --video ./ad-v3.mp4

# Analyze a YouTube video
/midflight --video https://youtube.com/watch?v=abc123

# Video with a specific question
/midflight --video ./ad-v3.mp4 Does this match the storyboard we discussed?

# Claude can also self-invoke when it recognizes it's stuck
# (after 3+ failed attempts, unfamiliar technology, etc.)

# Validate your MidFlight config and provider setup
/midflight-check-config
```

## Standalone CLI (use outside Claude Code)

The same engine that powers `/midflight` ships as a plain CLI, so you can get a
second opinion from a terminal, a script, or CI — no Claude Code required.
Inside Claude Code, the slash command summarizes the session for you; from the
terminal, you supply the question (and optionally the context) yourself.

### Install

`bin/midflight` is a self-contained wrapper over `scripts/query.sh`. Put it on
your `PATH` — a symlink keeps it pointed at the repo:

```bash
ln -s "$(pwd)/bin/midflight" /usr/local/bin/midflight
```

It reads the same `~/.config/mid-flight/config` and provider CLIs as the plugin
(see [Config](#config) and [Requirements](#requirements)).

### Usage

```bash
# Ask a question (defaults to consult mode)
midflight "should we use SSE or WebSockets for real-time updates?"

# Override the configured provider for one call
midflight -p gemini "is this regex vulnerable to ReDoS?"

# Fold a context file and matching source files into the question
midflight --context notes.md --include "src/*.ts" "where is the leak?"

# Delegate a precise change
midflight -m implement -f request.md

# Analyze a local or remote video (forces Gemini)
midflight --video ./ad-v3.mp4 "does this match the storyboard?"

# Send a pre-built query file straight to the engine
midflight -f query.md
```

| Option | Description |
|--------|-------------|
| `-m, --mode MODE` | `consult` (default), `implement`, or `video` |
| `-p, --provider NAME` | Override the configured provider (`codex`, `gemini`, `opencode`, `oz`) |
| `-c, --config FILE` | Use an alternate config file |
| `-f, --query-file FILE` | Send a pre-built query file straight to the engine |
| `--context FILE` | File whose contents become the Context section |
| `-i, --include GLOB` | Read matching files into the Context section (repeatable) |
| `--video FILE\|URL` | Analyze a video (forces video mode + Gemini) |
| `-h, --help` | Show help |
| `-V, --version` | Show version |

Run `midflight --help` for the full reference, or see
[docs/standalone-usage.md](docs/standalone-usage.md).

This is the standalone front door only — the Claude Code plugin behavior is
unchanged. The terminal CLI does not auto-summarize your working context the
way the `/midflight` slash command does; you provide the question and any
context you want included.

## Updating

```bash
claude plugin marketplace update mid-flight
claude plugin update mid-flight@mid-flight
```

## Uninstall

```bash
claude plugin remove mid-flight
claude plugin marketplace remove mid-flight
```

Restart Claude Code after uninstalling.

## Troubleshooting

If you want to validate your setup before running a real consult, use `/midflight-check-config`.

| Error | Cause | Fix |
|-------|-------|-----|
| `'codex' CLI not found` | Codex CLI not installed or not in PATH | Install from [github.com/openai/codex](https://github.com/openai/codex) |
| `'gemini' CLI not found` | Gemini CLI not installed or not in PATH | Install from [github.com/google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli) |
| `'opencode' CLI not found` | OpenCode CLI not installed or not in PATH | Install from [opencode.ai/docs/cli](https://opencode.ai/docs/cli/) |
| `'oz' CLI not found` | Oz CLI not installed or not in PATH | Install from [docs.warp.dev/reference/cli/cli](https://docs.warp.dev/reference/cli/cli) |
| `Codex query failed` | Auth issue or network error | Run `codex --version` to verify install, check API key |
| `Codex query failed` with `error: unexpected argument '--flag' found` in the details | Installed Codex CLI no longer accepts a flag MidFlight passes (e.g. `--full-auto`, removed in codex-cli 0.147.0) | Upgrade MidFlight; the failure is a CLI contract mismatch, not an auth problem |
| `OpenCode query failed` | Auth issue or provider error | Run `opencode --help` to verify install and confirm your provider credentials inside OpenCode |
| `Oz query failed` | Auth issue or provider error | Run `oz --help` or `oz whoami` to verify install and authentication |
| `Empty response` | Provider returned nothing | Try again or switch providers in config |
| `MidFlight hangs before Codex responds` | Codex inherited an open stdin stream from the caller and is waiting for EOF | Upgrade MidFlight; the wrapper now detaches stdin before invoking provider CLIs |
| `Video file exceeds 20MB limit` | Gemini CLI inline file limit | Compress or trim the video before analysis |
| `Could not determine file size` | `stat` failed on the video file | Check file permissions and path |

## Debugging

Run Claude Code with `claude --debug` to see query execution logs. All logs are prefixed with `[mid-flight]` on stderr and include mode, provider, query size, response size, and duration.

## Development

Run the shell regression suite with:

```bash
bash tests/run_all.sh
```

<details>
<summary><strong>Technical details</strong></summary>

### Architecture

MidFlight is a skill-based plugin (slash command). This is a deliberate design choice:

- **Skills run inside Claude's context** — Claude already knows everything about the current task, so there's no need for transcript parsing
- **Claude summarizes, not transcript extraction** — produces better, more focused context than any parsing could
- **On-demand, not automatic** — the user (or Claude itself) decides when a consultation would be valuable

### Query flow

1. `/midflight` invokes the skill, which instructs Claude to assess the situation
2. Claude writes a structured query (context + question) to a temp file
3. The query script (`scripts/query.sh`) reads the file, wraps it with a system prompt, and routes to the configured provider
4. The provider's response is returned to Claude via stdout
5. Claude presents the response with its own analysis (agreements, disagreements, recommended next steps)

### Provider abstraction

Providers are isolated behind separate functions (`query_codex`, `query_gemini`, `query_opencode`, `query_oz`) and a small config-driven router. Each provider handles its own CLI invocation details, while the shared runner handles log emission and user-facing failures consistently. Adding a new provider requires only a new function and a new case branch.

The `scripts/query.sh` entrypoint now delegates to helper modules under `scripts/lib/`, with prompts stored in `prompts/`. Each invocation gets its own temporary run workspace for staged inputs, prompt assembly, provider logs, and response capture.

MidFlight explicitly detaches stdin before launching provider CLIs. This avoids deadlocks when a caller leaves stdin connected to an open pipe; Codex will otherwise read piped stdin even when the main prompt is already supplied as an argument.

### Video analysis

Video mode accepts local files or URLs. Local files are copied to a temp staging directory and passed to Gemini CLI using the `@path` inline syntax. URLs are passed directly in the prompt and Gemini handles fetching natively. When a local file is staged, MidFlight passes that staging directory via `--include-directories` so Gemini can resolve the inline file reference. The staging dir is cleaned up on exit. Gemini CLI enforces a 20MB limit on inline files; the script validates this upfront.

### Self-invocation

The skill prompt includes guidance for when Claude should consider consulting an external model on its own — e.g., after multiple failed debugging attempts, when facing unfamiliar technology, or when two approaches seem equally valid. When self-invoking, Claude is instructed to be transparent about why.

</details>

## License

MIT
