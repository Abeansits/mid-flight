---
name: mid-flight
description: "Get a second opinion from Codex, Gemini, Antigravity, OpenCode, Oz, Grok, or Claude without leaving your current agent. Consult mode (advice only), implement mode (scoped file changes), or video mode (multimodal analysis). Use when you need an outside perspective, are stuck, or want architectural validation."
alwaysApply: false
metadata:
  author: Abeansits
  repository: https://github.com/Abeansits/mid-flight
  license: MIT
---

# MidFlight — Second Opinion from Another Agent

**Get a second opinion without context-switching.** You're mid-task, the approach feels right, but you want another model to validate it — or you need a precise change implemented by a different agent. MidFlight sends your current work to Codex, OpenCode, Oz, Antigravity, Gemini, Grok, or Claude, then brings their answer back.

No copy-paste. No rebuilding context. No tool-switching.

## When to use this skill

Invoke `/mid-flight` (or let the agent self-invoke) when:

- **Stuck after 3+ attempts** — different approaches all failed
- **Architectural validation** — before committing to a design
- **Technology uncertainty** — unfamiliar API or stack choice
- **Equal tradeoffs** — two valid approaches, need outside perspective
- **Cryptic errors** — debugging stalled after reasonable investigation
- **Video review** — analyze demo recordings or YouTube URLs

The agent should be transparent when self-invoking: "I'm consulting an external model because..."

## Three modes (inferred automatically)

MidFlight infers the mode from your question. When uncertain, defaults to **consult** (safe).

### 1. Consult (default)
Advice only, no file changes. Architecture, tradeoffs, sanity checks, debugging guidance.

```text
/mid-flight should we use SSE or WebSockets for real-time updates?
```

### 2. Implement
Precise, spec'd file changes executed by the external model. Use only when the change is narrow and well-defined.

```text
/mid-flight implement: add rate limiting to the /api/upload endpoint using sliding window, 10 req/min per user
```

### 3. Video
Analyze video files or YouTube URLs with multimodal models (Antigravity or Gemini).

```text
/mid-flight --video demo-v3.mp4 does this match the storyboard?
/mid-flight --video https://youtube.com/watch?v=... what accessibility issues do you see?
```

## How it works

### Prerequisites

**Required:** `bash` and **one provider CLI** on your `PATH`, authenticated:

- [Codex CLI](https://github.com/openai/codex) (default, most common)
- [Antigravity CLI](https://antigravity.google/docs/cli/install) (`agy`)
- [OpenCode CLI](https://opencode.ai/docs/cli/)
- [Oz CLI](https://docs.warp.dev/reference/cli/cli)
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) (enterprise/API-key only)
- [Grok Build CLI](https://docs.x.ai/build/cli/reference) (`grok`)
- [Claude Code CLI](https://code.claude.com/docs/en/headless) (`claude`)

**Install the engine:**

```bash
# Quick install (puts midflight on PATH)
curl -fsSL https://raw.githubusercontent.com/Abeansits/mid-flight/main/scripts/install.sh | bash

# Or from a checkout:
git clone https://github.com/Abeansits/mid-flight.git
cd mid-flight
./scripts/install.sh --from-dir . --prefix ~/.local
```

Verify:
```bash
midflight --version
```

### Provider notes

- **Cursor agents:** No `provider=cursor` yet (roadmap item). Default `provider=codex` works great — that's a different harness, not circular.
- **Grok Bot:** Automatically avoids circular `provider=grok` unless you pass `--allow-grok-provider`. Prefers `codex` → `agy` → `opencode` → `oz` → `gemini` → `claude`.
- **From Codex:** Avoids circular `provider=codex` unless `MIDFLIGHT_ALLOW_CODEX_PROVIDER=1`.

Configure via `~/.config/mid-flight/config`:
```
provider=codex
codex_model=gpt-5.4
codex_reasoning_effort=high
```

Full config reference: [README § Config](https://github.com/Abeansits/mid-flight#config)

## Agent instructions

When a user invokes `/mid-flight`:

### 1. Parse the invocation

- **`--video <file-or-url> [prompt]`** → video mode
- **Text question** → consult or implement (infer from specificity)
- **Empty** → identify what would most benefit from outside perspective

Optional flags:
- `--provider <name>` — override configured provider
- `--allow-grok-provider` — allow circular Grok → Grok (if on Grok Bot)
- `--allow-codex-provider` — allow circular Codex → Codex (if on Codex)

### 2. Classify intent

Set `MODE` based on the question:

- **`video`** — `--video` present
- **`consult`** — questions, tradeoffs, validation. **Default when uncertain.**
- **`implement`** — precise, actionable file-change spec only

### 3. Build context

For **consult** or **implement**, create a temporary query file:

```markdown
## Context
[Concise summary: what's being built, current state, key files, relevant errors/code snippets]

## Question
[Specific question or problem statement]
```

For **video**, prepare a prompt with session context:

```text
Context: [summary of what we're building and why this video matters]

Question: [user's question about the video]
```

### 4. Execute

Check if `midflight` is available:

```bash
command -v midflight >/dev/null 2>&1
```

#### If `midflight` is on PATH (recommended):

```bash
# Consult
midflight "$QUERY_FILE"

# Implement
midflight -m implement "$QUERY_FILE"

# Video with custom prompt
midflight --video "$VIDEO_PATH" "$VIDEO_PROMPT"

# Video with default breakdown
midflight --video "$VIDEO_PATH"

# Override provider
midflight --provider agy "$QUERY_FILE"
```

#### If `midflight` is not available:

**Fallback A (repo-local):** If this skill is in a mid-flight repo checkout:

```bash
bash "$(dirname "$SKILL_PATH")/../../scripts/query.sh" "$QUERY_FILE" consult
```

**Fallback B (Cloud Agent / teammate handoff):** When provider CLIs are unavailable:

1. Write the query to a shareable file (e.g., `/tmp/midflight-consult-${TIMESTAMP}.md`)
2. Suggest the user run it manually:
   ```bash
   midflight /tmp/midflight-consult-123456.md
   ```
3. Or (for Cursor Cloud Agents): use the `Task` tool to spawn a teammate agent with access to the provider CLI
4. For video: save the prompt and suggest manual review

**Inform the user:**
```text
I've prepared a consultation query, but the midflight engine isn't available.

Install it with:
  curl -fsSL https://raw.githubusercontent.com/Abeansits/mid-flight/main/scripts/install.sh | bash

Then run:
  midflight <query-file>

Alternatively, I can hand this off to a teammate or Cloud Agent with provider access.
```

### 5. Present findings

Share the external model's response, then add **your analysis**:

- Where you agree or disagree
- Recommended next step given both perspectives
- New concerns you hadn't considered
- For video: most actionable feedback and quality issues

**Example:**

```text
**Codex recommends:** Start with SSE.

Why:
- Updates are one-way server → client
- SSE fits existing HTTP auth
- Easier to debug and roll back

Watchouts:
- If client-to-server events become necessary, revisit WebSockets
- Confirm load balancer handles long-lived HTTP

---

**My take:** I agree. SSE is lower-risk and faster to ship. We can keep the event payload transport-agnostic so a future WebSocket move stays cheap.

**Next step:** Implement SSE for notifications. I'll add it now.
```

## Dual-consult (advanced)

Ask two providers the same question and compare answers:

```bash
midflight --dual agy "should we use SSE or WebSockets?"
# or explicit:
midflight --providers codex,agy "..."
```

Currently consult-only. Agents can run this manually and present both responses.

## Troubleshooting

**Validate setup:**
```bash
midflight --version
bash scripts/check-config.sh
```

**Common errors:**

| Error | Fix |
|---|---|
| `'codex' CLI not found` | [Install Codex](https://github.com/openai/codex) |
| `'agy' CLI not found` | [Install Antigravity](https://antigravity.google/docs/cli/install) |
| `Codex query failed` | Check auth: `codex --version` |
| `Empty response` | Retry or switch `provider=` in `~/.config/mid-flight/config` |
| `Video exceeds 20MB limit` | Compress or trim (Gemini inline-file limit) |

**Enable debug logging:**
```bash
export MIDFLIGHT_DEBUG=1
midflight <query>
```

## Configuration reference

Create `~/.config/mid-flight/config`:

```
provider=codex
codex_model=gpt-5.4
codex_reasoning_effort=high
agy_model=
agy_effort=
gemini_model=gemini-2.5-pro
```

Full settings: [README § Config](https://github.com/Abeansits/mid-flight#config)

## See also

- **Main README:** https://github.com/Abeansits/mid-flight#readme
- **Standalone CLI docs:** [docs/standalone-usage.md](https://github.com/Abeansits/mid-flight/blob/main/docs/standalone-usage.md)
- **Host-specific adapters:** `hosts/cursor/`, `hosts/grok/`, `hosts/codex/`
- **Provider capabilities:** [README § Providers](https://github.com/Abeansits/mid-flight#providers)

---

*MidFlight stays out of the way until you need an outside perspective. It doesn't replace your main agent — it gives them a teammate.*
