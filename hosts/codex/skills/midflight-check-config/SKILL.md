---
name: midflight-check-config
description: "Validate MidFlight config, provider availability, and video-mode prerequisites. Use when the user types $midflight-check-config or MidFlight setup looks broken."
---

# MidFlight Config Check (Codex host)

Run MidFlight's config validation and summarize the result.

## Engine resolution

Same rules as `$midflight`: `midflight` on `PATH`, else `$MIDFLIGHT_ROOT`, else walk up from this skill to a mid-flight checkout.

```bash
bash "<path-to-this-skill>/scripts/run.sh"
```

## Your job

1. Run the command above.
2. If it passes:
   - Confirm config looks healthy
   - Mention the active provider
   - Call out non-blocking warnings (e.g. neither `agy` nor Gemini for video)
3. If it fails:
   - List blocking issues clearly
   - Suggest the most direct fixes
   - Keep the response concise

Do not invent config problems. Report what the script says.

## Note on Codex hosts

If the active provider is `codex`, mention that `$midflight` will auto-prefer a non-Codex provider unless `MIDFLIGHT_ALLOW_CODEX_PROVIDER=1` is set — so having an alternate CLI (`agy`, `opencode`, `oz`, or `gemini`) on `PATH` is strongly recommended.
