---
name: midflight-check-config
description: Validate MidFlight config, provider availability, and video-mode prerequisites
model: opus
allowed-tools: Bash, Read
user-invocable: true
---

# MidFlight Config Check

Run MidFlight's config validation script and summarize the result for the user.

## Your job

1. Run:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-config.sh"
   ```

2. If the script passes:
   - Confirm that MidFlight's config looks healthy
   - Mention the active provider
   - Call out any non-blocking warnings, such as neither `agy` nor Gemini being available for video mode

3. If the script fails:
   - List the blocking issues clearly
   - Suggest the most direct fixes
   - Keep the response concise and actionable

Do not invent config problems. Report what the script says.
