---
name: midflight
description: Consult Codex or Gemini for a second opinion mid-development
model: opus
allowed-tools: Bash, Read, Glob, Grep, Write
user-invocable: true
---

# MidFlight — Mid-Development Consultation

You've been invoked to consult an external model (Codex or Gemini) for a second opinion. This could be user-triggered (`/midflight`) or self-triggered when you recognize you're stuck.

## Your job

1. **Assess the situation** — What are we working on? What's the current state? What specific problem or question needs outside perspective?

2. **Formulate the query** — Check if the user provided a question after `/midflight`:
   - If `$ARGUMENTS` contains a question, use that as the core question but still provide context.
   - If `$ARGUMENTS` is empty, identify what would most benefit from a second opinion based on the conversation so far (e.g., you're stuck debugging, choosing between approaches, unsure about an architecture decision).

3. **Classify intent** — Decide whether this is a consultation or an implementation request:

   - **`consult`** — Questions, tradeoff analysis, debugging help, architecture validation, "should we...", "what's the best way to...", or any request for advice/perspective. **When uncertain, default to consult.**
   - **`implement`** — Specific file changes with clear specs: "add X to file Y", "fix Z in W", complete code blocks with file paths. Only use this when the query contains precise, actionable implementation instructions.

   Set `INTENT="consult"` or `INTENT="implement"` based on the above.

4. **Write the query file** — Create a temp file with your context summary and question. This avoids shell escaping issues with large text.

   ```
   QUERY_FILE=$(mktemp "${TMPDIR:-/tmp}/midflight-query.XXXXXX")
   ```

   Write the file with this structure:

   ```markdown
   ## Context
   [Concise summary of what we're building, what's been done so far, and relevant technical details.
    Include specific file paths, error messages, or code snippets that are essential to understanding the situation.
    Be thorough but not verbose — the external model needs enough context to give useful advice.]

   ## Question
   [The specific question or problem. Be precise about what kind of help you need:
    a decision between approaches, debugging help, architecture validation, etc.]
   ```

5. **Call the query script**:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/query.sh" "$QUERY_FILE" "$INTENT"
   ```

   The script outputs the response to stdout. Capture it.

6. **Clean up** — Remove the temp query file.

7. **Present the findings** — Share the external model's response with the user. Add your own analysis:
   - Where do you agree or disagree with the external model's assessment?
   - What's the recommended next step given both perspectives?
   - If the external model raised concerns you hadn't considered, acknowledge them.

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

- If the query script fails, tell the user what happened and suggest they check their config (`~/.config/mid-flight/config`) and that the provider CLI is installed and authenticated.
- If the response is empty, note that the provider returned no response and suggest trying a different provider.
- Never crash the session or leave the user hanging — always communicate what happened.
