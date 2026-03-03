# Mid-Flight + Codex: Parallel Provider Dispatch Playbook

> Learnings from using OpenAI Codex (via mid-flight) alongside Claude subagents for parallel multi-provider implementation. Based on the channel discovery delete jobs feature (2026-03-02).

---

## The Pattern

Split implementation tasks by directory/service and dispatch to different AI providers in parallel. Codex handles one set of files while Claude handles another — zero conflicts, wall-clock time roughly halved.

```
Plan (10 tasks)
  ├── Backend tasks 1-6 ──→ Codex (via mid-flight, --full-auto)
  │   └── services/foundry/src/features/jobs/ (6 files)
  │
  └── Frontend tasks 7-8 ──→ Claude (subagent)
      └── apps/forge/src/lib/ (3 files)

Both run simultaneously → Review → Continue with remaining tasks
```

## What Worked Well

### Parallel dispatch by directory
Codex modified `services/foundry/` while Claude modified `apps/forge/`. Different directories, different concerns, zero merge conflicts. The key insight: **non-overlapping file trees are safe to parallelize across providers.**

### Codex in full-auto mode is a real implementer
`codex exec --full-auto` doesn't just consult — it reads existing files, makes edits, and runs verification commands. On this task:
- 6 files modified across 5 architectural layers
- All edits matched spec exactly on first try
- Ran `bun run check` and `bun run typecheck` itself
- 44,656 tokens used, ~2 minutes wall clock

### Natural provider-task mapping
Not all tasks are equal. The assignment that worked:

| Task type | Best provider | Why |
|-----------|--------------|-----|
| Pattern-following backend code | Codex | Well-specified, add-method-following-existing-pattern work |
| Multi-layer wiring (route → handler → service) | Codex | Mechanical, specs translate directly to code |
| React component restructuring | Claude | Needs nuanced understanding of component tree, state, and UX |
| UI interactions (dropdowns, callbacks, URL state) | Claude | Context-heavy, multiple interacting pieces |
| Review and verification | Claude | Needs judgment, not just execution |

### The query file format matters
Codex performed best with a highly structured query containing:
- Exact file paths with line numbers
- Complete code blocks (not "add something like...")
- Explicit ordering of changes
- Verification commands to run after

## What Was Rough

### 1. Manual query file construction
The 120-line markdown query had to be hand-crafted. Every file path, every line number, every code block — manually assembled. This is the biggest friction point and the most obvious automation opportunity.

### 2. No structured result parsing
Codex returned free-text output. To verify it actually made the right changes, I had to read every modified file manually. There's no machine-readable "here's what I changed" format to diff against expectations.

### 3. System prompt mismatch
Mid-flight's system prompt says: *"You are a senior engineer being consulted mid-development."* But we used it for implementation, not consultation. The instructions worked despite the framing, but a dedicated "implement" mode would be cleaner.

### 4. No rollback mechanism
If Codex had made bad edits, there's no atomic undo. The safest approach: `git stash` or snapshot before dispatching. We got lucky that everything was correct on the first try.

### 5. macOS mktemp quirk
`mktemp /tmp/midflight-query-XXXXXX.md` created a literal filename with X's instead of random characters. The `.md` suffix confuses mktemp on macOS. Use `mktemp /tmp/midflight-XXXXXXXX` without the extension instead.

### 6. No progress visibility
While Codex ran (background task), there was no streaming output. Just "running..." then done. For longer tasks, some progress indication would help.

## How To Use This Pattern

### Step 1: Prepare the query file

```bash
QUERY_FILE=$(mktemp "${TMPDIR:-/tmp}/midflight-query.XXXXXX")
cat > "$QUERY_FILE" << 'EOF'
## Context
[What we're building, tech stack, architecture patterns]
[Working directory path]
[List of files to modify]

## Question
Please implement these N changes:

### 1. `path/to/file.ts` — Description
[Exact code to add, with line numbers for placement]

### 2. `path/to/other-file.ts` — Description
[Exact code to add]

...

After making all changes, run [verification commands].
EOF
```

### Step 2: Dispatch in parallel

```
# Background: Codex for backend
Bash (run_in_background: true):
  bash "/path/to/mid-flight/scripts/query.sh" "$QUERY_FILE"

# Simultaneously: Claude subagent for frontend
Agent (run_in_background: true):
  subagent_type: general-purpose
  prompt: [frontend implementation instructions]
```

### Step 3: Verify both outputs

**Don't trust text reports.** Read the actual files:
- Compare each file against the spec
- Run typecheck and lint for both projects
- Check for unintended changes with `git diff --stat`

### Step 4: Review and commit

Standard review process, then single commit covering both providers' work.

## Configuration

### Mid-flight config
Location: `~/.config/mid-flight/config`

```
provider=codex
codex_model=gpt-5.3-codex
codex_reasoning_effort=high
```

### Codex execution mode
Mid-flight runs Codex with:
- `--full-auto` (no human approval needed)
- `--skip-git-repo-check` (works in any directory)
- `-o <output-file>` (captures response)
- Sandbox: `workspace-write` (can modify files in workdir and /tmp)
- Network access enabled

## Results from First Use

| Metric | Codex (backend) | Claude (frontend) |
|--------|-----------------|-------------------|
| Files modified | 6 | 3 |
| Tokens used | 44,656 | 30,459 |
| Tool calls | N/A (single exec) | 16 |
| Wall clock | ~2 min | ~1.5 min |
| First-try accuracy | 6/6 files correct | 3/3 files correct |
| Self-verified | Yes (ran check + typecheck) | Yes (ran check) |

Total: 9 files across 2 providers in ~2.5 minutes, all correct on first try.

## Future Ideas

1. **Auto-dispatch skill**: Reads a plan, splits tasks by directory, generates query files, dispatches to the right provider automatically
2. **Implement mode for mid-flight**: Different system prompt optimized for "make these exact changes" vs "give me advice"
3. **Structured output**: Codex returns a JSON manifest of changes for programmatic verification
4. **Git snapshot + rollback**: Auto-stash before dispatch, auto-rollback if verification fails
5. **Provider racing**: Send same task to both providers, use whichever produces better/faster result
6. **Streaming progress**: Tail Codex output file for real-time status during long tasks
7. **Verification framework**: Auto-diff modified files against expected state from the plan
