---
description: Update the CLAUDE.md memory section for the current life (internal helper)
disable-model-invocation: true
---

Update the CLAUDE.md memory section for the current life. This is typically called by other commands (/save-session, /compact-memory) but can be run manually.

## Steps

1. Detect the current life and project by reading `.claude-life` from this directory or parent directories. If no life found, tell the user and stop. If the life type is `workspace` and you're in a child directory, determine the project name.

2. Read the current memory files:
   - `~/.claude-lives/global/memory.md` (global preferences)
   - `~/.claude-lives/{life}/memory.md` (life memory)
   - **Flat life**: `~/.claude-lives/{life}/handover.md`
   - **Workspace project**: `~/.claude-lives/{life}/projects/{project}/memory.md` and `projects/{project}/handover.md`

3. Find the CLAUDE.md in the appropriate directory:
   - **Flat life**: the directory containing `.claude-life`
   - **Workspace project**: the project directory (first child under the life root)

4. Build the injection block using **progressive disclosure** (default) or **full** mode.

### Progressive mode (default)

Inject a compact ~500-token index that serves as a boot loader:

**Flat life:**
```
<!-- CLAUDE-LIVES:START:{life_name} -->
## Life: {life_name}

**Identity:** {1-line from Identity section}
**Focus:** {1-line from Current Focus}
**Last session:** {date from handover}
**Was doing:** {1-2 lines from What Was Happening}
**Next:** {top 3 next steps}

### Key Context
{top 5 facts from Key Context, compressed}

### Global
{2-3 lines of preferences, content only}

### Full Memory (read when needed)
- Life memory: `~/.claude-lives/{life}/memory.md`
- Handover: `~/.claude-lives/{life}/handover.md`
- Global: `~/.claude-lives/global/memory.md`
- Sessions: `~/.claude-lives/{life}/sessions/`

<!-- CLAUDE-LIVES:END -->
```

**Workspace project:**
```
<!-- CLAUDE-LIVES:START:{life_name} -->
## Life: {life_name} | Project: {project_name}

**Identity:** {1-line from life Identity}
**Focus:** {1-line from project Current Focus}
**Last session:** {date from project handover}
**Was doing:** {1-2 lines from project What Was Happening}
**Next:** {top 3 next steps from project}

### Life Context
{top 3 life-level key facts}

### Project Context
{top 5 project-specific key facts}

### Global
{2-3 lines of preferences}

### Full Memory (read when needed)
- Life memory: `~/.claude-lives/{life}/memory.md`
- Project memory: `~/.claude-lives/{life}/projects/{project}/memory.md`
- Project handover: `~/.claude-lives/{life}/projects/{project}/handover.md`
- Global: `~/.claude-lives/global/memory.md`
- Sessions: `~/.claude-lives/{life}/projects/{project}/sessions/`

<!-- CLAUDE-LIVES:END -->
```

### Full mode (use with `--full` argument)

Inject complete memory content (legacy, higher token usage):

```
<!-- CLAUDE-LIVES:START:{life_name} -->
## Life: {life_name}

### Global Preferences
{full content from global/memory.md}

### Life Memory
{full content from {life}/memory.md}

### Handover
{full content from {life}/handover.md}

<!-- CLAUDE-LIVES:END -->
```

5. If the CLAUDE.md already has `<!-- CLAUDE-LIVES:START:{life_name} -->` and `<!-- CLAUDE-LIVES:END -->` markers, replace everything between them (inclusive) with the new block.

6. If no markers exist, append the block to the end of CLAUDE.md.

7. Confirm what was updated and report approximate token count of the injected section.

$ARGUMENTS
