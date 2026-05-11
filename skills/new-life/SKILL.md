---
description: Create a new life context for claude-lives memory isolation
---

You are setting up a new "life" for the claude-lives memory system. A life is an isolated memory context tied to this directory tree. Everything in this directory and below will belong to this life.

## Step 1: Auto-Detect and Interview

**Auto-detect as much as possible before asking questions:**
- **Life name**: derive from the current directory basename (lowercase, hyphens for spaces). Example: `~/projects/my-research` → `my-research`
- **Stack**: scan for `package.json` (TypeScript/JS), `pyproject.toml`/`requirements.txt` (Python), `go.mod` (Go), `Cargo.toml` (Rust), `Makefile`/`CMakeLists.txt` (C/C++), `.swift` files (Swift)
- **Type hint**: if the current directory has multiple child directories each containing their own project markers (`.git`, `package.json`, etc.), suggest workspace; otherwise default to flat

**Ask only 2 questions** using AskUserQuestion (single batch):

1. **"What is this life about?"** (header: "Purpose")
   - Options: "PhD / Research", "Work / Professional", "Personal Project", "Side Project / Hobby"
   - multiSelect: false
   - description: This is used as your life's identity — how Claude understands this context

2. **"Is this one project, or a workspace containing multiple projects?"** (header: "Type")
   - Options: "Single project (Recommended)" (description: "This directory is one project — e.g., a repo, your PhD"), "Workspace" (description: "Contains multiple projects as child directories — e.g., ~/work")
   - multiSelect: false
   - Pre-select based on auto-detection hint above

The user can always pick "Other" to type a custom answer. Stack, tasks, and restrictions are inferred from the directory and populated with sensible defaults — the user can customize later via `/save-session` or direct memory edits.

## Step 2: Create the life

Based on the user's answers, determine:
- A short life name (lowercase, no spaces, e.g., "phd", "work", "design")
- A one-line description
- The type: `flat` if this is a single project, `workspace` if it contains multiple projects (from Q2)

Then create all required files:

### 2a. Create the `.claude-life` marker in the current directory

Write the file `.claude-life` with:
```yaml
name: {life_name}
created: {today's date YYYY-MM-DD}
description: {one-line description}
type: {flat or workspace}
token_budget:
  life: 4000
  handover: 1500
```

### 2b. Create the memory store

Create the directory `~/.claude-lives/{life_name}/` and populate it:

**`~/.claude-lives/{life_name}/memory.md`** — Initial memory from the interview:
```markdown
---
life: {life_name}
last_compressed: {today's date}
session_count: 0
---

# {life_name} — Life Memory

## Identity
{Summarize what this life is about from the user's purpose answer}

## Current Focus
{Infer from directory contents, or "Starting fresh" if unclear}

## Key Context
{Auto-detected stack + any context from user answers}

## Preferences
{Sensible defaults — user can customize later via /save-session}
```

**`~/.claude-lives/{life_name}/handover.md`**:
```markdown
---
life: {life_name}
last_updated: {today's date}
---

# Handover Notes

## What Was Happening
This life was just created. No previous session to hand over.

## Next Steps
{If the user is mid-way through something (Q5), list what they want to do next. Otherwise: "Ready for first session."}

## Pending Decisions
(None)

## Key Files Being Worked On
(None)
```

**`~/.claude-lives/{life_name}/config.yaml`**:
```yaml
life_token_budget: 4000
handover_token_budget: 1500
compression_threshold_pct: 80
decay_session_threshold: 10
```

**Create the directories:**
- `~/.claude-lives/{life_name}/sessions/`
- `~/.claude-lives/{life_name}/archive/`

**For workspace lives only**, also create:
- `~/.claude-lives/{life_name}/projects/` (projects are auto-initialized when you first work in a child directory)

### 2c. Create global memory if it doesn't exist

If `~/.claude-lives/global/memory.md` does not exist, create it:
```markdown
---
last_updated: {today's date}
---

# Global Preferences

These preferences apply across all lives.

## Communication Style
(Not yet configured)

## Tool Preferences
(Not yet configured)

## Formatting Preferences
(Not yet configured)
```

Also create `~/.claude-lives/global/config.yaml` if missing:
```yaml
global_token_budget: 1000
```

### 2d. Inject memory into CLAUDE.md

Check if a CLAUDE.md exists in the current directory.

Inject a **progressive disclosure** index (compact ~500-token summary) between markers:
```
<!-- CLAUDE-LIVES:START:{life_name} -->
## Life: {life_name}

**Identity:** {1-line summary}
**Focus:** {current focus or "Just created — ready for first session"}

### Key Context
{key tools, languages, workflows from interview}

### Global
{global preferences summary}

### Full Memory (read when needed)
- Life memory: `~/.claude-lives/{life_name}/memory.md`
- Handover: `~/.claude-lives/{life_name}/handover.md`
- Global: `~/.claude-lives/global/memory.md`
- Sessions: `~/.claude-lives/{life_name}/sessions/`

<!-- CLAUDE-LIVES:END -->
```

If no CLAUDE.md exists, create one with just the memory section.

IMPORTANT: Write memory content (memory.md, handover.md) in **compressed telegraphic style**: no filler, no articles, short phrases, one fact per line. This saves tokens on every future session.

## Step 3: Confirm

Tell the user:
- Life "{life_name}" created successfully (type: {flat or workspace})
- Memory store at `~/.claude-lives/{life_name}/`
- Marker at `.claude-life`
- CLAUDE.md updated with progressive index (~{N} tokens)
- They can now use `/save-session` to save work and `/resume` to pick up later
- If migrating from claude-mem: run `/import-claude-mem` to import existing data
- **For workspace lives**: explain that projects are auto-detected when working in child directories — no need to run any setup command per project

$ARGUMENTS
