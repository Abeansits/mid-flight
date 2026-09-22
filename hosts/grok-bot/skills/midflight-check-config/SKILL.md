---
name: midflight-check-config
description: "Validate MidFlight provider CLI setup and config. Use when troubleshooting provider errors or checking which providers are available."
disable-model-invocation: false
metadata:
  author: Abeansits
  short-description: Validate MidFlight config
---

# MidFlight Config Validation (Grok Bot host)

Validates that the MidFlight engine and at least one provider CLI are installed and authenticated.

## What it checks

- Engine resolution (PATH → MIDFLIGHT_ROOT → repo walk)
- Provider CLI availability (`codex`, `agy`, `opencode`, `oz`, `gemini`, `grok`, `claude`)
- Current config (`~/.config/mid-flight/config`)
- Basic auth smoke tests (version checks)

## Usage

```bash
/midflight-check-config
```

The skill will report which providers are available and show the current configuration.

## When to invoke

- First time using MidFlight
- After installing a new provider CLI
- When `/midflight` fails with a provider error
- To verify setup after changing `~/.config/mid-flight/config`

## Your job

1. **Run the check script:**

   ```bash
   bash "<path-to-this-skill>/scripts/run.sh"
   ```

2. **Present the output** — Show which providers are available, current config, and any issues.

3. **Suggest fixes** if problems are found:
   - Missing engine → install midflight CLI
   - No providers → install at least one provider CLI
   - Auth errors → run provider auth (e.g., `codex --version`, `agy login`)
   - Config issues → edit `~/.config/mid-flight/config`
