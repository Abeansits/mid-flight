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

## Important: Use the proper host adapter

This root-level skill is a **reference guide**. For actual invocation, install the host-specific adapter:

- **Cursor Grok Bot:** `hosts/grok-bot/` ([README](https://github.com/Abeansits/mid-flight/tree/main/hosts/grok-bot))
- **Cursor agents:** `hosts/cursor/` ([README](https://github.com/Abeansits/mid-flight/tree/main/hosts/cursor))
- **xAI Grok Build CLI:** `hosts/grok/` ([README](https://github.com/Abeansits/mid-flight/tree/main/hosts/grok))
- **OpenAI Codex CLI:** `hosts/codex/` ([README](https://github.com/Abeansits/mid-flight/tree/main/hosts/codex))
- **Claude Code:** Plugin via `claude plugin marketplace add Abeansits/mid-flight` ([README](https://github.com/Abeansits/mid-flight#1-claude-code-plugin))

Each host adapter wires the shared MidFlight engine (`bin/midflight` / `scripts/query.sh`) properly for that environment.

## Three modes (inferred automatically)

MidFlight infers the mode from your question. When uncertain, defaults to **consult** (safe).

### 1. Consult (default)
Advice only, no file changes. Architecture, tradeoffs, sanity checks, debugging guidance.

```text
/midflight should we use SSE or WebSockets for real-time updates?
```

### 2. Implement
Precise, spec'd file changes executed by the external model. Use only when the change is narrow and well-defined.

```text
/midflight implement: add rate limiting to the /api/upload endpoint using sliding window, 10 req/min per user
```

### 3. Video
Analyze video files or YouTube URLs with multimodal models (Antigravity or Gemini).

```text
/midflight --video demo-v3.mp4 does this match the storyboard?
/midflight --video https://youtube.com/watch?v=... what accessibility issues do you see?
```

## Quick install for Grok Bot / Cursor

```bash
# 1. Install engine
curl -fsSL https://raw.githubusercontent.com/Abeansits/mid-flight/main/scripts/install.sh | bash

# 2. Install provider CLI (e.g., Codex)
# See: https://github.com/openai/codex

# 3. Copy host adapter skills to ~/.cursor/skills/
mkdir -p ~/.cursor/skills
cp -R hosts/grok-bot/skills/midflight ~/.cursor/skills/midflight        # for Grok Bot
# OR
cp -R hosts/cursor/skills/midflight ~/.cursor/skills/midflight          # for Cursor agents
```

Full instructions: [README § Install for Grok Bot / Cursor](https://github.com/Abeansits/mid-flight#install-for-grok-bot--cursor)

## Provider notes

- **Cursor Grok Bot / Cursor agents:** No `provider=cursor` exists yet. Default `provider=codex` is fine (external consult).
- **Grok Build CLI:** Has circular guard to avoid `provider=grok` on Grok Build host unless `--allow-grok-provider` passed.
- **Codex CLI:** Has circular guard to avoid `provider=codex` on Codex host unless `MIDFLIGHT_ALLOW_CODEX_PROVIDER=1` set.

Configure via `~/.config/mid-flight/config`:
```
provider=codex
codex_model=gpt-5.4
codex_reasoning_effort=high
```

Full config reference: [README § Config](https://github.com/Abeansits/mid-flight#config)

## When to invoke

- **Stuck after 3+ attempts** — different approaches all failed
- **Architectural validation** — before committing to a design
- **Technology uncertainty** — unfamiliar API or stack choice
- **Equal tradeoffs** — two valid approaches, need outside perspective
- **Cryptic errors** — debugging stalled after reasonable investigation
- **Video review** — analyze demo recordings or YouTube URLs

## Troubleshooting

If `/midflight` fails, run `/midflight-check-config` (or `midflight --version` from terminal) to validate setup.

**Common errors:**

| Error | Fix |
|---|---|
| `midflight not found` | Install: `curl -fsSL https://raw.githubusercontent.com/Abeansits/mid-flight/main/scripts/install.sh \| bash` |
| `'codex' CLI not found` | Install provider: [Codex](https://github.com/openai/codex) |
| `Codex query failed` | Check auth: `codex --version` |
| `Empty response` | Retry or switch `provider=` in `~/.config/mid-flight/config` |

Debug logging: `export MIDFLIGHT_DEBUG=1`

## See also

- **Main README:** https://github.com/Abeansits/mid-flight#readme
- **Provider capabilities:** [README § Providers](https://github.com/Abeansits/mid-flight#providers)
- **Host adapters:** `hosts/cursor/`, `hosts/grok-bot/`, `hosts/grok/`, `hosts/codex/`

---

*MidFlight stays out of the way until you need an outside perspective. It doesn't replace your main agent — it gives them a teammate.*
