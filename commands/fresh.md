---
description: Save session and clear — single command to transition between tasks
---

Save the current session and prepare for a clean start. Use this instead of manually running `/save-session` then `/clear`.

## Steps

Run the **full /save-session workflow** first:

1. **Detect life and project** — find `.claude-life`, determine life name, type, and project
2. **Read current state** — load memory.md and handover.md (project-level if workspace)
3. **Write session summary** — write session log to the appropriate sessions/ directory
4. **Update handover** — write what was happening, next steps, pending decisions, key files
5. **Merge into memory** — add new facts, update changed facts, remove completed items (telegraphic style)
6. **Update CLAUDE.md** — refresh the progressive index between markers
7. **Write .last-saved marker** — timestamp to the appropriate directory

Then:

8. **Confirm and instruct**:
   ```
   Session saved. Now run /clear to start fresh.
   Your context is preserved in CLAUDE.md — Claude will have it automatically on the next message.
   ```

The user only needs to type `/fresh` and then `/clear`. No `/resume` needed afterward — the progressive block in CLAUDE.md provides session context automatically.

## Why not just /clear?

`/clear` is a built-in Claude Code command that executes instantly — Claude cannot intercept it to save first. This command ensures your work is saved before you clear.

$ARGUMENTS
