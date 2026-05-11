---
description: Save a mid-session snapshot to preserve context before auto-compaction
---

Write an incremental snapshot of work done so far in this session. This preserves early context that would be lost if Claude Code auto-compacts the conversation.

## Steps

1. **Detect life and project**: Look for `.claude-life` in this directory or parent directories. Determine the project name if workspace type. If no life found, use `~/.claude-lives/global/`.

2. **Find snapshot directory**: The snapshot scratch files are at:
   - **Flat life**: `~/.claude-lives/{life}/.session-snapshots/`
   - **Workspace project**: `~/.claude-lives/{life}/projects/{project}/.session-snapshots/`
   - **No life**: `~/.claude-lives/global/.session-snapshots/`

   If the directory doesn't exist, create it and initialize `counter` (set to 0), `snapshots.md` (empty), and `session-id` (current timestamp + life + project).

3. **Count existing snapshots**: Count `<!-- snapshot:N` markers in `snapshots.md` to determine the next snapshot number.

4. **Write snapshot**: Append to `snapshots.md`:

   ```markdown
   <!-- snapshot:{N} t:{ISO8601_UTC} tools:{counter_value} -->
   ## Snapshot {N}
   - {telegraphic bullet: what you did}
   - {telegraphic bullet: decisions made}
   - {telegraphic bullet: dead ends or important context}
   ```

   Write 3-6 bullets covering work since the last snapshot (or session start if this is snapshot 1). Use compressed telegraphic style (no articles, infinitive verbs, short phrases).

5. **Reset counter**: Write `0` to the `counter` file.

6. **Confirm**: Tell the user:
   ```
   Checkpoint {N} saved. ({token_estimate} tokens)
   Early work is preserved against compaction.
   ```

$ARGUMENTS
