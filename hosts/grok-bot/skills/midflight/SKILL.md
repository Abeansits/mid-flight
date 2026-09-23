---
name: midflight
description: "Consult Codex, Gemini, Antigravity, OpenCode, Oz, Grok, or Claude for a second opinion mid-development, or analyze video with Antigravity/Gemini. Use when the user types /midflight, asks for an outside take, or you are stuck after multiple failed approaches."
disable-model-invocation: false
metadata:
  author: Abeansits
  short-description: Outside-model consult via MidFlight
---

# MidFlight — Mid-Development Consultation (Grok Bot host)

You've been invoked to consult an **external** model through MidFlight's configured provider for a second opinion. This can be user-triggered (`/midflight`) or self-triggered when you recognize you're stuck.

Supports text consultation, implementation delegation, and **video analysis**.

## Provider note (no circular guard needed)

There is **no** `provider=grok-bot` or `provider=cursor` in MidFlight today. Running this skill from Grok Bot with the default `provider=codex` (or `agy` / `opencode` / `oz` / `gemini`) is the intended path — those are different harnesses, not a circular self-consult.

This is Cursor's **Grok Bot**, not xAI's Grok Build CLI. For Grok Build, see `hosts/grok/` which has a circular guard.

## Engine resolution

Call the bundled runner (it finds the engine for you):

```bash
bash "<path-to-this-skill>/scripts/run.sh" ...
```

Resolution order inside the runner:

1. `midflight` on `PATH` (preferred)
2. `$MIDFLIGHT_ROOT` (clone or install prefix with `bin/` + `scripts/`)
3. Walk up from this skill to a mid-flight checkout (repo-local / symlink installs)

If resolution fails, tell the user to install the standalone CLI (`ln -s …/bin/midflight` onto `PATH`) or set `MIDFLIGHT_ROOT`.

## Your job

1. **Assess the situation** — What are we working on? What's the current state? What needs outside perspective?

2. **Parse arguments** — Check the user's invocation for flags and content:

   - **`--video <file-or-url>`** — Video analysis. Extract the video source and any remaining text as the question/prompt.
   - **Text question** — Standard text consultation.
   - **Empty** — Identify what would most benefit from a second opinion from the conversation so far.
   - **`--provider <name>`** — Forward to the runner if present (`codex`, `agy`, `opencode`, `oz`, `gemini`, `grok`, `claude`).

3. **Classify intent** — Set `INTENT` to one of:

   - **`video`** — `--video` present. Engine auto-switches to Antigravity/Gemini as needed.
   - **`consult`** — Questions, tradeoffs, debugging, architecture validation. **When uncertain, default to consult.**
   - **`implement`** — Precise, actionable file-change instructions only.

4. **Build and call**

   ### For `consult` or `implement`

   Write a temp query file:

   ```bash
   QUERY_FILE=$(mktemp "${TMPDIR:-/tmp}/midflight-query.XXXXXX")
   ```

   Structure:

   ```markdown
   ## Context
   [Concise summary: what's being built, what's done, essential paths/errors/snippets.]

   ## Question
   [Specific question or problem.]
   ```

   Call:

   ```bash
   bash "<path-to-this-skill>/scripts/run.sh" "$QUERY_FILE" "$INTENT"
   ```

   ### For `video`

   ```bash
   # Custom prompt (include session context):
   bash "<path-to-this-skill>/scripts/run.sh" "$VIDEO_FILE" video "$VIDEO_PROMPT"

   # Default scene breakdown:
   bash "<path-to-this-skill>/scripts/run.sh" "$VIDEO_FILE" video
   ```

   When building `VIDEO_PROMPT`:

   ```text
   Context: [summary]

   Question: [user question about the video]
   ```

5. **Present the findings** — Share the external response, then add your analysis:

   - Where you agree or disagree
   - Recommended next step given both perspectives
   - New concerns you hadn't considered
   - For video: most actionable feedback and quality issues


## Dual-consult (via CLI)

Same question to two providers — print both answers. Prefer the standalone CLI:

```bash
midflight --dual agy "should we use SSE or WebSockets?"
# or explicit: midflight --providers codex,agy "…"
```

Consult-only in v1. Hosts do not need a separate dual UX; run the CLI (or tell the user to) and present both labeled sections.

## When to self-invoke

Consider invoking `/midflight` yourself when:

- You've tried **3+ different approaches** without success
- You're uncertain about a **technology or API** and want validation
- Two approaches seem **equally valid** and tradeoffs aren't clear
- You've hit an **error you can't diagnose** after reasonable investigation
- Requirements are complex and you want to **sanity-check architecture** before building

Be transparent: tell the user you're consulting an external model and why.

## Error handling

- If the runner fails, report the error and suggest `/midflight-check-config` plus checking `~/.config/mid-flight/config` and that the provider CLI is installed/authenticated.
- If the response is empty, note that and suggest another provider.
- Never crash the session or leave the user hanging.
