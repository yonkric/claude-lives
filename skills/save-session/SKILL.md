---
description: Save current session context to life memory (run before ending or /clear)
---

Save everything important from this session to your life memory so it persists across `/clear` and future sessions.

## Step 1: Detect Life and Project

Find the current life by looking for a `.claude-life` file in this directory or parent directories. Read it to get the life name and type (flat or workspace). If no life is found, tell the user: "No life detected. Run /new-life to create one." and stop.

If the life type is `workspace` and you're in a child directory, determine the project name (first directory component under the life root). The project is auto-initialized if it doesn't have storage yet.

## Step 2: Read Current State

**For flat lives**, read:
- `~/.claude-lives/{life}/memory.md` — current life memory
- `~/.claude-lives/{life}/handover.md` — current handover notes

**For workspace projects**, read:
- `~/.claude-lives/{life}/memory.md` — life-level memory (shared context)
- `~/.claude-lives/{life}/projects/{project}/memory.md` — project memory
- `~/.claude-lives/{life}/projects/{project}/handover.md` — project handover

## Step 2.5: Read Session Snapshots

Check for snapshot files that were captured during this session:
- **Flat life**: `~/.claude-lives/{life}/.session-snapshots/snapshots.md`
- **Workspace project**: `~/.claude-lives/{life}/projects/{project}/.session-snapshots/snapshots.md`
- **No life**: `~/.claude-lives/global/.session-snapshots/snapshots.md`

If `snapshots.md` exists and is non-empty, read it. These snapshots contain incremental summaries of work done earlier in the session — work that may have been lost to auto-compaction. Use them as **additional context** when writing the session summary in Step 3.

If no snapshots exist, continue normally (this is the common case for short sessions).

## Step 3: Write Session Summary

Reflect on what happened this session. Synthesize BOTH the snapshots from Step 2.5 (covering early/mid-session work) AND your current in-memory context (covering recent work). Write a session log to the appropriate sessions directory:
- **Flat life**: `~/.claude-lives/{life}/sessions/{YYYY-MM-DD}-{NNN}.md`
- **Workspace project**: `~/.claude-lives/{life}/projects/{project}/sessions/{YYYY-MM-DD}-{NNN}.md`

NNN is the next sequence number (001, 002, etc.) for today.

The session log format:
```markdown
---
date: {YYYY-MM-DD}
session: {NNN}
life: {life_name}
---

## Summary
{2-3 sentence summary of what happened}

## Decisions Made
{Bullet list of key decisions, or "(None)" if no significant decisions}

## Completed
{Bullet list of things finished}

## Pending
{Bullet list of things started but not finished}

## Key Findings
{Any important discoveries, insights, or context learned}

## Dead Ends
{Approaches tried and abandoned — include only if any exist. These are often lost to compaction and are valuable to preserve.}
```

If snapshots were available from Step 2.5, ensure the session log covers the FULL session timeline — not just recent work. Deduplicate facts that appear in both snapshots and current memory. Mark approaches that were tried and abandoned as "Dead Ends" (these are typically only visible in snapshots, not current context).

## Step 4: Update Handover

Write the handover file with what the NEXT session needs to know:
- **Flat life**: `~/.claude-lives/{life}/handover.md`
- **Workspace project**: `~/.claude-lives/{life}/projects/{project}/handover.md`

```markdown
---
life: {life_name}
last_updated: {YYYY-MM-DD}
---

# Handover Notes

## What Was Happening
{What we were literally doing when the session ended — be specific}

## Next Steps
{Concrete list of what to do next, in priority order}

## Pending Decisions
{Any decisions that need to be made}

## Key Files Being Worked On
{List specific file paths that were being edited}
```

## Step 5: Merge New Information into Memory

Read the current memory file and update it:
- **Flat life**: update `~/.claude-lives/{life}/memory.md`
- **Workspace project**: update `~/.claude-lives/{life}/projects/{project}/memory.md` for project-specific facts. Only update the life-level `~/.claude-lives/{life}/memory.md` if you learned something broadly relevant to the life (not project-specific).

Update by:

1. **Adding** genuinely new facts (new tools adopted, new goals, new context learned)
2. **Updating** facts that changed (status changed, focus shifted)
3. **NOT duplicating** facts already present
4. **Removing** completed items that are no longer relevant
5. **Preserving** the existing structure (Identity, Current Focus, Key Context, Preferences sections)

### Compression Style (IMPORTANT)

Write all memory content in **compressed telegraphic style** to maximize information per token:

- **No filler words**: drop articles (a, an, the), drop "is/are/was/were" when meaning is clear
- **Infinitive verbs**: "Fix auth bug" not "Fixed the authentication bug"
- **Short phrases over sentences**: "PyTorch 2.1, CUDA 12.2, A100 GPU" not "We are using PyTorch version 2.1 with CUDA 12.2 on an A100 GPU"
- **Collapse redundancy**: merge overlapping facts into one line
- **No meta-commentary**: no "This section contains..." or "The following are..."
- **Dash-prefix lists**: use `- fact` format, one fact per line
- **Abbreviate when clear**: "ch4" not "chapter 4", "env" not "environment", "config" not "configuration"

Example — before (47 tokens):
```
We are currently working on chapter 4 of the thesis, which focuses on
transformer architectures and their applications to natural language
processing tasks.
```

Example — after (14 tokens):
```
Writing ch4: transformer architectures, NLP applications
```

This compression style applies to ALL memory writes: memory.md, handover.md, and session logs.

Update the frontmatter: increment `session_count`, update `last_compressed` if you significantly changed the memory.

IMPORTANT: Keep memory.md under the token budget. Check the config at `~/.claude-lives/{life}/config.yaml` for `life_token_budget` (default 4000 tokens, roughly 16000 characters). If memory **exceeds 80%** of the budget after your updates, **automatically run the /compact-memory workflow inline** (deduplicate, archive old sessions, decay stale facts) instead of just warning the user. This prevents memory bloat for users who never run /compact-memory manually.

## Step 6: Update CLAUDE.md

Find the CLAUDE.md in the life's root directory (the directory containing `.claude-life`). Update the memory section between the `<!-- CLAUDE-LIVES:START:{life} -->` and `<!-- CLAUDE-LIVES:END -->` markers using **progressive disclosure** format.

The injected section should be a **compact index** (~500 tokens), NOT the full memory. It serves as a boot loader that tells Claude what this life is and where to find full details:

```
<!-- CLAUDE-LIVES:START:{life_name} -->
## Life: {life_name}

**Identity:** {1-line from Identity section}
**Focus:** {1-line from Current Focus section}
**Last session:** {date}
**Was doing:** {1-2 lines from handover What Was Happening}
**Next:** {top 3 next steps from handover}

### Key Context
{top 5 most important facts from Key Context, compressed}

### Global
{2-3 lines of global preferences, content only}

### Full Memory (read when needed)
- Life memory: `~/.claude-lives/{life}/memory.md`
- Handover: `~/.claude-lives/{life}/handover.md`
- Global: `~/.claude-lives/global/memory.md`
- Sessions: `~/.claude-lives/{life}/sessions/`

<!-- CLAUDE-LIVES:END -->
```

If the markers don't exist in CLAUDE.md, append this section to the end of the file.

## Step 7: Mark Session as Saved

Write a `.last-saved` timestamp to the appropriate directory so the Session Protocol can distinguish saved from unsaved sessions:
- **Flat life**: `~/.claude-lives/{life}/.last-saved`
- **Workspace project**: `~/.claude-lives/{life}/projects/{project}/.last-saved`

Content: current UTC timestamp in ISO 8601 format (e.g., `2026-05-08T14:30:00Z`).

## Step 7.5: Clean Up Snapshots

Delete the `.session-snapshots/` directory for the active life/project (or global). The snapshots have been incorporated into the session log and are no longer needed.

- **Flat life**: `rm -rf ~/.claude-lives/{life}/.session-snapshots/`
- **Workspace project**: `rm -rf ~/.claude-lives/{life}/projects/{project}/.session-snapshots/`
- **No life**: `rm -rf ~/.claude-lives/global/.session-snapshots/`

## Step 8: Confirm

Tell the user what was saved:
- Session log written to: {path}
- Handover updated
- Memory updated (mention if any new facts were added)
- CLAUDE.md updated (progressive index, ~{N} tokens)
- Full memory token usage: {current}/{budget}
- If snapshots were merged: "Merged {N} mid-session snapshots into session log"

If memory exceeded 80% of budget and you ran auto-compact, mention: "Auto-compacted memory ({before}→{after} tokens) to stay within budget."

$ARGUMENTS
