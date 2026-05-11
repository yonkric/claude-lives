---
description: Temporarily view another life's memory without switching contexts
---

Temporarily access another life's memory for cross-referencing. This does NOT change your current life or modify any memory files.

## Usage
`/borrow {life_name}` — borrow from another life
`/borrow {life_name}/{project_name}` — borrow from a specific project in a workspace life

## Steps

1. **Parse argument**: The argument can be a life name (e.g., "phd", "work") or a life/project path (e.g., "work/project-a"). If no argument provided, scan `~/.claude-lives/` for available lives and use **AskUserQuestion** to let the user pick:
   - **"Which life do you want to borrow from?"** (header: "Life")
     - Options: list up to 4 available lives (label: life name, description: one-line from memory.md identity or config). For workspace lives with projects, include "life/project" entries as options where relevant.
     - multiSelect: false

2. **Validate**: Check that the target memory exists:
   - For a life: `~/.claude-lives/{life_name}/memory.md`
   - For a project: `~/.claude-lives/{life_name}/projects/{project_name}/memory.md`
   
   If not found, tell the user what's available and stop.

3. **Read the borrowed memory**:
   - For a life: Read `memory.md` and `handover.md`
   - For a project: Read the project's `memory.md` and `handover.md`, plus the parent life's `memory.md` for context

4. **Present it clearly**:

```
## Borrowed Context: {life_name}{" / " + project_name if project}

> This is a read-only view. It is NOT injected into your current life.
> After /clear, this borrowed context will be gone.

### {target} Memory
{content from memory.md, without frontmatter}

### {target} Last Handover
{content from handover.md, without frontmatter}
```

5. **Remind the user**: "You're still in your current life ({current_life}). This borrowed context is temporary — it won't persist after `/clear` and won't affect your life's memory."

## Important Rules
- Do NOT modify the borrowed life's memory or handover
- Do NOT modify the current life's memory with borrowed content
- Do NOT inject borrowed content into the current life's CLAUDE.md
- This is read-only cross-referencing only

$ARGUMENTS
