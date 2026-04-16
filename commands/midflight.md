---
name: midflight
description: Consult Codex, Gemini, OpenCode, or Oz for a second opinion mid-development, or analyze video with Gemini
model: opus
allowed-tools: Bash, Read, Glob, Grep, Write
user-invocable: true
---

# MidFlight — Mid-Development Consultation

You've been invoked to consult an external model through MidFlight's configured provider (Codex, Gemini, OpenCode, or Oz) for a second opinion. This could be user-triggered (`/midflight`) or self-triggered when you recognize you're stuck.

Supports text consultation, implementation delegation, and **video analysis** (scene breakdowns, ad review, quality checks).

## Your job

1. **Assess the situation** — What are we working on? What's the current state? What specific problem or question needs outside perspective?

2. **Parse arguments** — Check `$ARGUMENTS` for flags and content:

   - **`--video <file-or-url>`** — If present, this is a video analysis request. Extract the video source (local path or URL) and any remaining text as the question/prompt.
     - Example: `--video /path/to/ad.mp4 Does this match the storyboard?`
     - Example: `--video https://youtube.com/watch?v=abc123`
     - Example: `--video ./demo.mp4` (no question = default scene breakdown)
   - **Text question** — If no `--video` flag, treat as a standard text consultation (same as before).
   - **Empty** — Identify what would most benefit from a second opinion based on the conversation so far.

3. **Classify intent** — Decide the mode based on the arguments:

   - **`video`** — When `--video` flag is present. Always uses Gemini (multimodal required).
   - **`consult`** — Questions, tradeoff analysis, debugging help, architecture validation, "should we...", "what's the best way to...", or any request for advice/perspective. **When uncertain, default to consult.**
   - **`implement`** — Specific file changes with clear specs: "add X to file Y", "fix Z in W", complete code blocks with file paths. Only use this when the query contains precise, actionable implementation instructions.

   Set `INTENT` to `"video"`, `"consult"`, or `"implement"` based on the above.

4. **Build and call** — The approach differs based on intent:

   ### For `consult` or `implement` (text modes)

   Write a temp query file with context and question:

   ```
   QUERY_FILE=$(mktemp "${TMPDIR:-/tmp}/midflight-query.XXXXXX")
   ```

   Structure:

   ```markdown
   ## Context
   [Concise summary of what we're building, what's been done so far, and relevant technical details.
    Include specific file paths, error messages, or code snippets that are essential to understanding the situation.
    Be thorough but not verbose — the external model needs enough context to give useful advice.]

   ## Question
   [The specific question or problem. Be precise about what kind of help you need:
    a decision between approaches, debugging help, architecture validation, etc.]
   ```

   Call:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" "$QUERY_FILE" "$INTENT"
   ```

   ### For `video` (video analysis mode)

   If the user provided a question alongside `--video`, combine it with session context into a single prompt string. If no question was provided, the script uses a default scene breakdown prompt.

   Call with the video file path as arg1, `video` as arg2, and the optional prompt as arg3:

   ```bash
   # With custom prompt (includes session context):
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" "$VIDEO_FILE" video "$VIDEO_PROMPT"

   # With default scene breakdown:
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" "$VIDEO_FILE" video
   ```

   When building `VIDEO_PROMPT` with session context, structure it as:

   ```
   VIDEO_PROMPT="Context: [summary of what we're building and relevant details]

   Question: [the user's question about the video]"
   ```

   **Note:** Video mode auto-switches to Gemini regardless of config. No need to check the provider.

5. **Present the findings** — Share the external model's response with the user. Add your own analysis:
   - Where do you agree or disagree with the external model's assessment?
   - What's the recommended next step given both perspectives?
   - If the external model raised concerns you hadn't considered, acknowledge them.
   - For video analysis: highlight the most actionable feedback and any quality concerns.

   Format your response clearly so the user can quickly understand the consultation result and make a decision.

## When to self-invoke

Consider calling `/midflight` yourself (via the Skill tool) when:

- You've tried **3+ different approaches** to the same problem without success
- You're working with a **technology or API you're uncertain about** and want to validate your approach
- Two or more approaches seem **equally valid** and the tradeoffs aren't clear
- You've hit an **error you can't diagnose** after reasonable investigation
- The user's requirements are complex and you want to **sanity-check your architecture** before building

When self-invoking, be transparent: tell the user you're consulting an external model and why.

## Error handling

- If the query script fails, tell the user what happened and suggest they check their config (`~/.config/mid-flight/config`) and that the selected provider CLI is installed and authenticated.
- If the response is empty, note that the provider returned no response and suggest trying a different provider.
- Never crash the session or leave the user hanging — always communicate what happened.
