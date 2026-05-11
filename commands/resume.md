---
description: Resume where you left off — read handover notes and life memory
---

Pick up exactly where the last session left off. This command reads full memory files (not just the compact CLAUDE.md index) to give you complete context.

## Steps

1. **Detect life and project**: Look for `.claude-life` in this directory or parent directories. If not found, say "No life detected" and stop. If the life type is `workspace` and you're in a child directory, determine the project name.

2. **Read handover**: 
   - **Flat life**: Read `~/.claude-lives/{life}/handover.md`
   - **Workspace project**: Read `~/.claude-lives/{life}/projects/{project}/handover.md`
   
   This tells you what was literally happening when the last session ended.

3. **Read memory**:
   - **Always**: Read `~/.claude-lives/{life}/memory.md` for life-level context (identity, key facts, preferences)
   - **Workspace project**: Also read `~/.claude-lives/{life}/projects/{project}/memory.md` for project-specific context

4. **Read global preferences**: Read `~/.claude-lives/global/memory.md` for cross-life preferences.

5. **Check for unsaved sessions**: Read the session metadata and saved marker in the appropriate directory:
   - **Flat life**: `~/.claude-lives/{life}/.last-session-meta.json` and `~/.claude-lives/{life}/.last-saved`
   - **Workspace project**: `~/.claude-lives/{life}/projects/{project}/.last-session-meta.json` and `.../.last-saved`
   
   Stale detection logic:
   - If `.last-session-meta.json` exists and has `"significant": true`:
     - If `.last-saved` doesn't exist, or `.last-session` timestamp is newer than `.last-saved`: the previous session was likely NOT saved
     - Show: "Previous session had {N} messages and {M} file modifications but was not saved. That context is no longer in the conversation. Check `git log` or recent file changes if you need to reconstruct what happened."
     - Do NOT suggest running `/save-session` — the previous conversation context is gone and saving now would capture nothing useful.
   - If `.last-session-meta.json` has `"significant": false`: skip the warning (trivial session)
   - **Fallback** (no meta file): compare `.last-session` timestamp vs latest file in `sessions/`. If `.last-session` is newer, show: "A previous session may not have been saved. Check recent file changes if something is missing."

6. **Check for preserved snapshots**: Read the session metadata from Step 5. If `"has_snapshots": true`, check for snapshot files:
   - **Flat life**: `~/.claude-lives/{life}/.session-snapshots/snapshots.md`
   - **Workspace project**: `~/.claude-lives/{life}/projects/{project}/.session-snapshots/snapshots.md`
   
   If the file exists and is non-empty:
   - Read the snapshots
   - Count them (`<!-- snapshot:N` markers)
   - Include in the brief: "Previous session had {N} mid-session snapshots with partial work captured. This context was NOT saved to the session log but IS available."
   - Ask: "Want me to review the preserved snapshots and incorporate them into memory?"
   - If the user accepts: read the snapshots, merge relevant facts into memory.md and handover.md, then delete the `.session-snapshots/` directory.
   - If the user declines: leave the snapshots in place (they'll be cleaned up on next session start).

7. **Brief the user**: Present a concise summary:

```
## Resuming: {life_name}{" | Project: " + project_name if workspace}

**Last session:** {date from handover}

**What we were doing:**
{from handover "What Was Happening"}

**Next steps:**
{from handover "Next Steps"}

**Pending decisions:**
{from handover "Pending Decisions", or skip if none}

**Key files:**
{from handover "Key Files Being Worked On", or skip if none}
```

8. **Ask**: "Ready to continue, or would you like to review anything first?"

NOTE: The CLAUDE.md memory section uses progressive disclosure — it contains a compact index (~500 tokens) with file paths. This /resume command reads the FULL memory files to give you complete context. You do not need to re-read the files listed in CLAUDE.md after running /resume.

$ARGUMENTS
