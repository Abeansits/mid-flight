# mid-flight

#### On-demand consultation with Codex or Gemini at any point during development. Get a second opinion when you're stuck, validate an approach before committing to it, analyze video content, or sanity-check an architecture decision — without leaving your Claude Code session.

A [Claude Code](https://claude.ai/code) plugin that provides ad-hoc consultations with the [Codex](https://github.com/openai/codex) or [Gemini](https://github.com/google-gemini/gemini-cli) CLI. Supports text-based consultation, implementation delegation, and **video analysis** via Gemini's multimodal capabilities.

Companion to [pre-flight](https://github.com/abeansits/pre-flight), which reviews plans automatically. MidFlight is for everything that happens *after* planning.

## How it works

1. You're mid-development and want a second opinion
2. Run `/midflight should we use WebSockets or SSE here?` (or just `/midflight` and Claude figures out what to ask)
3. Claude summarizes the current context and question
4. The query is sent to your configured provider (Codex or Gemini)
5. Claude presents the external model's perspective alongside its own analysis

No transcript parsing, no hooks — Claude already has full context, so it writes a concise summary and question directly.

## How it's different from pre-flight

| | pre-flight | mid-flight |
|---|---|---|
| **Trigger** | Automatic (ExitPlanMode hook) | Manual (`/midflight`) or Claude-initiated |
| **Context** | Plan file (extracted from transcript) | Claude's own summary (already has full context) |
| **Purpose** | Catch plan issues before approval | Get unstuck, validate approaches, second opinions |
| **Mechanism** | Hook + deny/retry pattern | Skill (slash command) + query script |

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
- `bash` in your PATH

## Install

```bash
claude plugin marketplace add Abeansits/mid-flight
claude plugin install mid-flight@mid-flight
```

Restart Claude Code after installing.

## Config

Create `~/.config/mid-flight/config` to override defaults:

```
provider=codex
codex_model=gpt-5.3-codex
codex_reasoning_effort=high
gemini_model=gemini-2.5-pro
```

| Setting                  | Default          | Description                         |
|--------------------------|------------------|-------------------------------------|
| `provider`               | `codex`          | Query provider (`codex` or `gemini`) |
| `codex_model`            | `gpt-5.3-codex`  | Codex model to use                  |
| `codex_reasoning_effort` | `high`           | Reasoning effort (low/medium/high)  |
| `gemini_model`           | `gemini-2.5-pro` | Gemini model to use                 |

Separate config from pre-flight so you can use different models/settings for ad-hoc queries vs plan reviews.

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
```

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

| Error | Cause | Fix |
|-------|-------|-----|
| `'codex' CLI not found` | Codex CLI not installed or not in PATH | Install from [github.com/openai/codex](https://github.com/openai/codex) |
| `'gemini' CLI not found` | Gemini CLI not installed or not in PATH | Install from [github.com/google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli) |
| `Codex query failed` | Auth issue or network error | Run `codex --version` to verify install, check API key |
| `Empty response` | Provider returned nothing | Try again or switch providers in config |
| `MidFlight hangs before Codex responds` | Codex inherited an open stdin stream from the caller and is waiting for EOF | Upgrade MidFlight; the wrapper now detaches stdin before invoking provider CLIs |
| `Video file exceeds 20MB limit` | Gemini CLI inline file limit | Compress or trim the video before analysis |
| `Could not determine file size` | `stat` failed on the video file | Check file permissions and path |

## Debugging

Run Claude Code with `claude --debug` to see query execution logs. All logs are prefixed with `[mid-flight]` on stderr and include mode, provider, query size, response size, and duration.

<details>
<summary><strong>Technical details</strong></summary>

### Architecture

MidFlight is a skill-based plugin (slash command), not a hook-based plugin like pre-flight. This is a deliberate design choice:

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

Same pattern as pre-flight: separate functions (`query_codex`, `query_gemini`) behind a config-driven router. Adding a new provider requires only a new function and case branch.

MidFlight explicitly detaches stdin before launching provider CLIs. This avoids deadlocks when a caller leaves stdin connected to an open pipe; Codex will otherwise read piped stdin even when the main prompt is already supplied as an argument.

### Video analysis

Video mode accepts local files or URLs. Local files are copied to a temp staging directory and passed to Gemini CLI using the `@path` inline syntax. URLs are passed directly in the prompt — Gemini handles fetching natively. Local files are sandboxed: the staging dir is the only path exposed via `--include-directories`, so the parent directory is never accessible to Gemini. The staging dir is cleaned up on exit. Gemini CLI enforces a 20MB limit on inline files; the script validates this upfront.

### Self-invocation

The skill prompt includes guidance for when Claude should consider consulting an external model on its own — e.g., after multiple failed debugging attempts, when facing unfamiliar technology, or when two approaches seem equally valid. When self-invoking, Claude is instructed to be transparent about why.

</details>

## License

MIT
