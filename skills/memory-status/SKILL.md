---
description: Show current life memory status — token usage, last save, session count
---

Display the current state of your life memory system.

## Steps

1. **Detect life and project**: Look for `.claude-life` in this directory or parent directories. If the life type is `workspace` and you're in a child directory, determine the project name.

2. **If life found**, read and display:

   **Life Info:**
   - Read `.claude-life` to get life name, description, and type (flat/workspace)
   - Read `~/.claude-lives/{life}/config.yaml` for token budgets

   **Memory Usage (flat life):**
   - Read `~/.claude-lives/{life}/memory.md` — count approximate tokens (file size in bytes / 4)
   - Read `~/.claude-lives/{life}/handover.md` — count approximate tokens
   - Read `~/.claude-lives/global/memory.md` — count approximate tokens
   - Calculate total and percentage of budget

   **Memory Usage (workspace project):**
   - Read `~/.claude-lives/{life}/memory.md` — life-level tokens
   - Read `~/.claude-lives/{life}/projects/{project}/memory.md` — project tokens
   - Read `~/.claude-lives/{life}/projects/{project}/handover.md` — project handover tokens
   - Read `~/.claude-lives/global/memory.md` — global tokens
   - Calculate total and percentage of budget

   **Session History:**
   - Count files in the appropriate sessions directory (flat: `{life}/sessions/`, project: `{life}/projects/{project}/sessions/`)
   - Count files in the appropriate archive directory
   - Read `session_count` from memory.md frontmatter

   **Freshness:**
   - Read `last_compressed` from memory.md frontmatter
   - Read `last_updated` from handover.md frontmatter
   - Read `.last-session` timestamp from the appropriate directory
   - Compare .last-session to latest session log to check if last session was saved

   **Token Economics (from `.last-session-meta.json`):**
   - Read `session_tokens` from the meta file in the appropriate directory
   - This is the approximate token cost of the last session (transcript size / 4)
   - Read memory token total — this is the "recovered" context (tokens of past work available without re-doing it)
   - Also scan all `.last-session-meta.json` files to sum cumulative `session_tokens` if available

3. **Display in this format:**

```
## Memory Status: {life_name}{" | Project: " + project_name if workspace}

**Description:** {from .claude-life}
**Type:** {flat or workspace}
**Life root:** {directory containing .claude-life}
{If workspace: **Project:** {project_name} (auto-detected from directory)}

### Token Usage
| Layer | Tokens | Budget | Usage |
|-------|--------|--------|-------|
| Global | {n} | {budget} | {%}% |
| Life Memory | {n} | {budget} | {%}% |
{If workspace: | Project Memory | {n} | {budget} | {%}% |}
| Handover | {n} | {budget} | {%}% |
| **Total** | **{n}** | **{budget}** | **{%}%** |

### Session History
- Total sessions: {session_count from frontmatter}
- Pending (unarchived) logs: {count in sessions/}
- Archived months: {count in archive/}
{If workspace: - Other projects in this life: {list project dirs under projects/}}

### Freshness
- Last memory compression: {date}
- Last handover update: {date}
- Last session end: {.last-session timestamp, or "unknown"}
- Previous session saved: {Yes/No/Unknown}

### Token Economics
- Last session cost: ~{session_tokens from .last-session-meta.json} tokens
- Memory store size: ~{total memory tokens} tokens (this is past work you don't need to redo)
- Memory efficiency: {total memory tokens} tokens of context from {session_count} sessions
{If session_tokens available: "Your memory recovers ~{total memory tokens} tokens of context at a cost of ~{CLAUDE.md index size} tokens per session (progressive index)."}

{If usage > 80%: "Memory approaching budget limit. Consider running `/compact-memory`."}
{If pending logs > 5: "Several unarchived session logs. Consider running `/compact-memory` to merge them."}
```

4. **If no life found:**
```
No life detected in this directory.

Run `/new-life` to create a life context, or navigate to a directory with a `.claude-life` marker.

Existing lives:
{List directories in ~/.claude-lives/ that are not "global"}
```

$ARGUMENTS
