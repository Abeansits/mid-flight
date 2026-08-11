# Standalone CLI usage

`bin/midflight` is a thin wrapper over MidFlight's engine (`scripts/query.sh`)
that lets you consult Codex, Gemini, OpenCode, or Oz from any terminal, script,
or CI job — without Claude Code.

The engine was always standalone; this wrapper just adds friendly argument
parsing, help/version output, and inline-question assembly. The Claude Code
plugin behavior is unchanged.

## What it does (and doesn't) do

Inside Claude Code, `/midflight` writes the context summary for you because
Claude already has the full session. From the terminal there is no session to
summarize, so **you** supply the question and any context you want to include.
The wrapper assembles a `## Context` / `## Question` query file from what you
pass and hands it to the engine — it does not call a model to summarize for you.

## Install

`bin/midflight` is self-contained and finds the engine relative to its own
(symlink-resolved) location, so a symlink on your `PATH` works from anywhere:

```bash
ln -s "$(pwd)/bin/midflight" /usr/local/bin/midflight
midflight --version
```

You can also run it in place with `./bin/midflight ...`.

### Prerequisites

- `bash`
- A provider CLI in `PATH` (`codex`, `gemini`, `opencode`, or `oz`), installed
  and authenticated.
- Optionally `~/.config/mid-flight/config` to pick the provider and models.
  Without it, the engine's defaults apply (provider `codex`). See the
  [README config section](../README.md#config).

## Options

```
midflight [OPTIONS] [QUESTION...]

  -m, --mode MODE        consult | implement | video   (default: consult)
  -p, --provider NAME    codex | gemini | opencode | oz (overrides config)
      --model MODEL      model to use for the active provider (overrides config)
  -c, --config FILE      use an alternate config file
  -f, --query-file FILE  send a pre-built query file straight to the engine
      --context FILE     file whose contents become the Context section
  -i, --include GLOB     read matching files into the Context section (repeatable)
      --video FILE|URL   analyze a video (forces video mode + Gemini)
      --timeout SECONDS  hard bound on provider call (default off; N>0 enables
                         portable watchdog + pg kill, no coreutils needed)
  -h, --help             show help
  -V, --version          show version
```

## Examples

```bash
# Consult (default)
midflight "should we use SSE or WebSockets for real-time updates?"

# Override the provider for a single call
midflight -p gemini "is this regex vulnerable to ReDoS?"

# Override both provider and model
midflight -p gemini --model gemini-2.5-flash "quick take on this approach"

# Include context + source files
midflight --context recent-debug.md --include "src/**/*.ts" \
  "why does the worker hang on shutdown?"

# Repeatable --include
midflight -i "src/auth/*.ts" -i "README.md" "is the token TTL sane?"

# Implementation delegation
midflight -m implement -f request.md

# Video analysis (auto-switches to Gemini regardless of config)
midflight --video ./ad-v3.mp4 "does this match the storyboard we discussed?"
midflight --video https://youtube.com/watch?v=abc123

# Full back-compat: hand the engine a query file you built yourself
midflight -f query.md
```

## How input is assembled

- **Inline question** — `[QUESTION...]` becomes the `## Question` section. Any
  `--context` file and `--include` globs are read and placed in a `## Context`
  section above it.
- **`--query-file FILE`** — passed to the engine untouched (full compatibility
  with the existing `scripts/query.sh` contract). Cannot be combined with an
  inline question, `--context`, or `--include`.
- **`--video FILE|URL`** — forces video mode and Gemini. Trailing text is the
  prompt; with no prompt the engine uses its default scene-breakdown prompt.

## Provider and config overrides

`-p/--provider`, `--model`, and `-c/--config` let you change the provider, model,
or config for a single call without editing your real config. The wrapper composes
an effective config in a temporary home and points the engine at it, while symlinking
the rest of your home directory through so provider CLIs keep their authentication.
Your `~/.config/mid-flight/config` is never modified.

`--model` maps to the appropriate config key based on the active provider:
- `-p codex --model gpt-5` → sets `codex_model`
- `-p gemini --model gemini-2.5-flash` → sets `gemini_model`
- `--model gemini-2.5-flash` (no `-p`) → sets the model for whatever provider is
  active in your config
- `--video clip.mp4 --model gemini-2.5-flash` → sets `gemini_model`; video mode
  always runs on Gemini, so the override follows it there

## Exit codes

- `0` — success (provider response on stdout; `[mid-flight]` logs on stderr).
- `2` — usage error (bad mode, missing question, conflicting flags, missing
  files passed to `--context`/`--config`/`--query-file`).
- `1` — engine/provider error (missing provider CLI, invalid config, auth or
  network failure). These messages come straight from the engine.
