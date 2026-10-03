# Standalone CLI usage

`bin/midflight` is the terminal front door. It parses arguments, assembles a
query, and calls the engine (`scripts/query.sh`) so you can consult Codex,
Gemini, Antigravity, OpenCode, Oz, Grok, or Claude from a terminal, script, or
CI job. Host skills call the same engine.

`midflight --help` is the short calling contract (exit codes, streams, stdout
shape, `-p` limits). This guide is the longer one: install, how a query is
built, and sandbox limits.

## What it does (and doesn't) do

Inside Claude Code, `/midflight` writes the context summary for you because
Claude already has the full session. From the terminal there is no session to
summarize, so **you** supply the question and any context you want to include.
The CLI assembles a `## Context` / `## Question` query file from what you
pass and hands it to the engine — it does not call a model to summarize for you.

## Install

`bin/midflight` finds the engine relative to its own symlink-resolved location.

Homebrew is the supported install. The formula is `Formula/midflight.rb` in this repo. Pass the git URL because the repo is not named `homebrew-*`.

```bash
brew tap Abeansits/mid-flight https://github.com/Abeansits/mid-flight
brew install Abeansits/mid-flight/midflight
midflight --version
```

`brew install` uses the tagged release named in the formula. `brew install --HEAD Abeansits/mid-flight/midflight` tracks `main`.

Without Homebrew, clone the repo and run the binary in place, or set `MIDFLIGHT_ROOT` to that checkout:

```bash
git clone https://github.com/Abeansits/mid-flight.git
cd mid-flight
./bin/midflight --version
export MIDFLIGHT_ROOT="$(pwd)"
```

If an older `scripts/install.sh` copy is still on `PATH`, remove it before `brew install`. The old default directory was `/usr/local` when that directory was writable, otherwise `~/.local`.

```bash
rm -f ~/.local/bin/midflight /usr/local/bin/midflight
rm -rf ~/.local/lib/mid-flight /usr/local/lib/mid-flight
```

### Prerequisites

- `bash`
- A provider CLI in `PATH` (`codex`, `agy`, `gemini`, `opencode`, `oz`, `grok`, or `claude`),
  installed and authenticated.
- Optionally `~/.config/mid-flight/config` to pick the provider and models.
  Without it, the engine's defaults apply (provider `codex`). See the
  [README config section](../README.md#config).

## Options

```
midflight [OPTIONS] [QUESTION...]
midflight --image-gen PROMPT
midflight --video-gen PROMPT

  -m, --mode MODE        consult | implement | video   (default: consult)
  -p, --provider NAME    codex | gemini | agy | opencode | oz | grok | claude (overrides config)
      --dual PROVIDER    dual-consult: primary from -p/config, plus PROVIDER (consult-only)
      --providers A,B    dual-consult with both providers named explicitly (consult-only)
      --model MODEL      model to use for the active provider (overrides config; not with dual)
  -c, --config FILE      use an alternate config file
  -f, --query-file FILE  send a pre-built query file straight to the engine
      --context FILE     file whose contents become the Context section
  -i, --include GLOB     read matching files into the Context section (repeatable)
      --git-status       append current branch + `git status` under Context
      --diff             append `git diff` (working tree) and staged diff under Context
      --video FILE|URL   analyze a video (keeps agy or gemini; else agy on PATH, else Gemini)
      --image-gen PROMPT generate one image with Grok or Codex and print the file path
      --video-gen PROMPT generate one video with Grok and print the file path.
                         Asks for 720p when image_to_video lists resolution_name.
                         The saved file can be smaller.
      --ref FILE         reference image for --image-gen or --video-gen (repeatable).
                         On a video, the first file is the opening frame and sets the shape.
      --aspect RATIO     1:1, 16:9, 9:16, 3:2, or 2:3.
                         On a video, a readable PNG or JPEG that conflicts
                         with --aspect exits 2. An unreadable frame warns
                         on stderr and continues.
      --timeout SECONDS  hard bound on each provider call (default off; N>0 enables
                         portable watchdog + pg kill; dual ≈ 2N wall)
  -h, --help             show help
  -V, --version          show version
```

Consult passes a read-only flag only when that CLI has one MidFlight can trust for a single run. Codex uses `--sandbox read-only`. Grok uses `--sandbox read-only`. Project writes are blocked, and `~/.grok` and temp stay writable. Claude uses `--permission-mode plan`. Implement uses Codex `--sandbox workspace-write`, Grok `--always-approve` with the sandbox left off, and `--dangerously-skip-permissions` for Antigravity and Claude. Image generation and video generation stay writable.

Antigravity, Gemini, OpenCode, and Oz consults do not get a read-only flag. Antigravity headless mode auto-allows workspace file writes even when `--dangerously-skip-permissions` is omitted. For those providers the consult prompt is an instruction, and writes follow that CLI's permission settings. Limits are in the README section [Consult and file writes](../README.md#consult-and-file-writes).

### Dual-consult

Same question to two providers; print both answers. That is the product.

Primary UX:

```bash
midflight --dual agy "should we use SSE or WebSockets?"
midflight -p codex --dual grok "should we use SSE or WebSockets?"
```

Explicit form (names both sides):

```bash
midflight --providers codex,agy "should we use SSE or WebSockets?"
```

Rules:

- **Consult-only** — `--dual` / `--providers` refuse `implement`, `video`, `--image-gen`, and `--video-gen` with a clear usage error.
- Sequential engine runs (same assembled query file / `--query-file`).
- Stdout is a labeled dump (`## Provider A` / `## Provider B`) plus a short `## Where they differ` note that is structural only (identical-after-trim, or “compare them yourself”). MidFlight does **not** invent a merged opinion or LLM disagreement analysis.
- If one provider fails, the successful answer is still printed and the failed side shows its error; exit status is `1`.
- `--timeout` applies per side (~2N wall-clock for dual).
- `--model` is not combined with dual (set per-provider models in config). `--dual` and `--providers` are mutually exclusive; `--providers` also rejects a simultaneous `-p`.

### Git-derived context

`--git-status` and `--diff` let the standalone CLI build a useful Context section
from the current repo without hand-writing notes (and without Claude summarizing
a session):

- `--git-status` — current branch (`git branch --show-current`) plus
  `git status` (color off)
- `--diff` — `git diff` (working tree) and `git diff --cached` (staged); empty
  sides are marked `(empty)`

Both are combinable with `--context`, `-i/--include`, and an inline question.
They require `git` on `PATH` and a work tree (clear exit 2 otherwise).

Each git section is capped at **100 KiB (102400 bytes)**. Oversized output is
truncated and ends with a `[midflight: truncated …]` marker. Raise the cap with
`MIDFLIGHT_GIT_CONTEXT_MAX_BYTES` (positive integer bytes).

## Examples

```bash
# Consult (default)
midflight "should we use SSE or WebSockets for real-time updates?"

# Override the provider for a single call
midflight -p agy "is this regex vulnerable to ReDoS?"

# Dual-consult (same question → two providers)
midflight --dual agy "SSE or WebSockets?"
midflight --providers codex,agy "SSE or WebSockets?"

# Override both provider and model
midflight -p agy --model gemini-3.1-pro-high "quick take on this approach"

# Include context + source files
midflight --context recent-debug.md --include "src/**/*.ts" \
  "why does the worker hang on shutdown?"

# Repo-derived Context (branch/status and/or working-tree + staged diffs)
midflight --git-status --diff "does this change look right?"

# Repeatable --include
midflight -i "src/auth/*.ts" -i "README.md" "is the token TTL sane?"

# Implementation delegation
midflight -m implement -f request.md

# Video analysis (keeps agy or gemini; otherwise agy on PATH, else Gemini)
midflight --video ./ad-v3.mp4 "does this match the storyboard we discussed?"
midflight --video https://youtube.com/watch?v=abc123

# Image generation (Grok or Codex; prints the saved file path)
midflight --image-gen "a paper plane over a fjord"
midflight -p codex --image-gen "a paper plane over a fjord"

# Video generation (Grok only; prints the saved file path)
midflight --video-gen "the paper plane banks once and levels out"
midflight --image-gen "a paper plane over a fjord" --aspect 16:9 --ref plane.png

# Full back-compat: hand the engine a query file you built yourself
midflight -f query.md
```

## How input is assembled

- **Inline question** — `[QUESTION...]` becomes the `## Question` section. Any
  `--context` file, `--include` globs, and `--git-status` / `--diff` output are
  placed in a `## Context` section above it.
- **`--query-file FILE`** — passed to the engine untouched (full compatibility
  with the existing `scripts/query.sh` contract). Cannot be combined with an
  inline question, `--context`, `--include`, `--git-status`, or `--diff`.
- **`--video FILE|URL`** — forces video mode. A configured or `-p` provider of
  `agy` or `gemini` stays. Any other provider prefers `agy` on `PATH`, else
  Gemini. Trailing text is the prompt; with no prompt the engine uses its
  default scene-breakdown prompt.
- **Stdin** — ignored. `echo question | midflight` exits 2 (`midflight: …` on
  stderr, empty stdout). Pass the question as arguments. `--` ends options, so
  a question that starts with `-` is `midflight -- -question`.
- **`--image-gen PROMPT`** — generates one image and prints the saved file path.
  Grok and Codex are the providers. With no `-p`, a config provider of `grok`
  or `codex` is kept; any other config uses `grok` when that CLI is on `PATH`,
  otherwise Codex when that CLI is on `PATH`, otherwise `grok`. The prompt is
  the image description. `--video` stays analysis.
- **`--video-gen PROMPT`** — generates one video with Grok and prints the saved
  file path. `-p` must be `grok` when it is passed. With no `-p`, a `grok`
  config is kept; any other config uses Grok. `--video` stays analysis.
  The prompt asks `image_to_video` for 720p when that tool lists
  `resolution_name`. The public video API uses a different field,
  `resolution`, and also documents `1080p`. MidFlight does not read a live
  Grok Build schema, so a missing field or a lower tier can save a smaller
  file. There is no `--resolution` flag.
- **`--ref FILE`** — reference image for `--image-gen` or `--video-gen`. Repeat
  it for more than one file. On an image, the files are the edit source. On a
  video, the first file is the opening frame and sets the shape. A portrait
  target needs a 9:16 opening frame. A 16:9 target needs a 16:9 opening frame.
  Later files guide the clip. They do not replace that frame. Codex also
  receives each file with `codex exec -i`.
- **`--aspect RATIO`** — `1:1`, `16:9`, `9:16`, `3:2`, or `2:3`. Grok gets that
  ratio on a new image. Codex image generation gets the matching pixel size
  (`16:9` is `1536x864`). A video with no `--ref` sets the ratio on the still
  that starts the clip. With a first `--ref`, that frame's shape wins, and
  `--aspect` is not passed to `image_to_video`. A different ratio is an error
  before the run when the frame is a readable PNG or JPEG. An unreadable frame
  prints a note on stderr and continues. The saved path stays on stdout.

## Provider and config overrides

`-p/--provider`, `--model`, and `-c/--config` let you change the provider, model,
or config for a single call without editing your real config. The CLI composes
an effective config in a temporary home and points the engine at it, while symlinking
the rest of your home directory through so provider CLIs keep their authentication.
Your `~/.config/mid-flight/config` is never modified.

`--model` maps to the appropriate config key based on the active provider:
- `-p codex --model gpt-6-sol` → sets `codex_model`
- `-p gemini --model gemini-3.1-pro-preview` → sets `gemini_model`
- `-p agy --model gemini-3.1-pro-high` → sets `agy_model`
- `--model gemini-3.8-flash` (no `-p`) → sets the model for whatever provider is
  active in your config
- `--video clip.mp4 --model gemini-3.8-flash` (no `-p`) → sets `agy_model` and
  `gemini_model`. A configured `agy` or `gemini` stays; otherwise video prefers
  `agy` on `PATH`, else Gemini

## Exit codes

- `0` — success. The provider reply is on stdout. `[mid-flight]` logs are on
  stderr. `--image-gen` and `--video-gen` print one absolute path.
- `2` — usage error. The line is `midflight: …` on stderr and stdout is empty.
  That covers a bad mode, a missing question, conflicting flags, missing files
  passed to `--context` / `--config` / `--query-file`, dual-consult misuse
  (implement, video, image-gen, video-gen, the same provider twice,
  `--dual` with `--providers`, `--model` with dual, an unknown dual name),
  `--git-status` / `--diff` outside a git work tree or without `git` on `PATH`,
  a readable PNG or JPEG opening frame that conflicts with `--aspect`, and an
  `-p` value `--image-gen` or `--video-gen` rejects.
- `1` — engine or provider error. `Error: …` is on stdout and `[mid-flight]`
  logs are on stderr. That covers a missing provider CLI, invalid config
  (including an unknown `-p` on a single consult), auth or network failure,
  and dual-consult when either side fails (the other answer is still printed).
  If image or video generation runs and saves no new file, exit 1 and the
  note is on stderr.
