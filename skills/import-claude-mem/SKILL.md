---
description: Import memories from claude-mem into claude-lives
---

You are helping the user migrate their data from claude-mem (the previous memory system) into claude-lives. This converts claude-mem observations and session summaries into claude-lives memory files.

This command supports two modes:
- **Per-directory mode** (default): Run from inside a project directory. Imports the matching claude-mem project for this directory only, and sets up the life here.
- **Bulk mode** (`--all`): Imports all claude-mem projects at once, then asks which directories to connect them to.

## Step 1: Detect claude-mem

Check if the claude-mem database exists:

1. Look for `~/.claude-mem/claude-mem.db`
2. If not found, tell the user: "No claude-mem database found at ~/.claude-mem/claude-mem.db. If your database is elsewhere, run `/import-claude-mem --db /path/to/db`."

If found, read the database to discover projects:

```bash
sqlite3 ~/.claude-mem/claude-mem.db "SELECT project, COUNT(*) as obs FROM observations GROUP BY project ORDER BY obs DESC"
```

Also get summary counts:
```bash
sqlite3 ~/.claude-mem/claude-mem.db "SELECT project, COUNT(*) as sums FROM session_summaries GROUP BY project ORDER BY sums DESC"
```

Show the user what was found:
```
Found claude-mem database with N projects:

| Project | Observations | Summaries |
|---------|-------------|-----------|
| my-research | 150     | 20        |
| work        | 80      | 12        |
```

## Step 2: Determine mode and select project(s)

### Per-directory mode (no `--all` flag)

This is the default. Detect the current working directory and try to match it to a claude-mem project:

1. **Check for existing `.claude-life`**: If the current directory already has a `.claude-life` marker, read the life name from it. Use that to find the matching claude-mem project.

2. **Auto-detect by directory name**: If no `.claude-life` exists, use the current directory's name as a hint. For example, if you're in `~/projects/my-research`, look for a claude-mem project named "PHD" (case-insensitive match).

3. **Show matches and ask**: Use **AskUserQuestion** to confirm the import. If a best match is found, present it as the recommended first option:

   Use AskUserQuestion with 1-2 questions:
   - **"Which claude-mem project should be imported for this directory?"** (header: "Project")
     - First option: the best match with "(Recommended)" — e.g., label: "my-research (Recommended)", description: "150 observations, 20 summaries"
     - Additional options: other top projects from the database (up to 3 more options total)
     - multiSelect: false
   - **"Life name for this directory?"** (header: "Name")
     - First option: suggested default — e.g., label: "my-research (Recommended)", description: "Derived from project name, lowercase"
     - Second option: directory-name based alternative if different
     - multiSelect: false

   Convert to valid life name: lowercase, spaces to hyphens. Only alphanumeric, hyphens, and underscores allowed.

### Workspace-aware mode (run from a workspace or directory with child project folders)

If the current directory has a `.claude-life` with `type: workspace`, OR has multiple child directories containing project markers (`.git`, `package.json`, etc.), use workspace-aware import:

1. **Scan child directories**: list immediate subdirectories that look like projects
2. **Match against claude-mem projects**: for each child directory, try to find a matching claude-mem project by name (case-insensitive, fuzzy — e.g., child dir `my-research` matches claude-mem project `MY-RESEARCH` or `my_research`)
3. **Present the mapping** in a table:
   ```
   Proposed import mapping:
   
   | Directory        | claude-mem Project | Observations | Summaries |
   |------------------|--------------------|-------------|-----------|
   | ./claude-lives/  | claude-lives       | 50          | 8         |
   | ./my-research/   | PHD                | 150         | 20        |
   | ./work-tool/     | (no match)         | —           | —         |
   ```
4. **Ask for confirmation** using AskUserQuestion:
   - **"Import these matched projects into the workspace?"** (header: "Import")
     - "Yes, import all matched (Recommended)" (description: "Imports {N} matched projects, skips unmatched directories")
     - "Let me adjust the mapping" (description: "Review and change matches before importing")
     - "Import all claude-mem projects" (description: "Import everything, including projects without matching directories")
     - multiSelect: false

5. For matched projects, import directly into the workspace project structure at `~/.claude-lives/{workspace}/projects/{dir-name}/`
6. For unmatched claude-mem projects, ask where to put them or skip

### Bulk mode (`--all` flag)

Import all projects regardless of directory structure. Show the proposed mapping, then use **AskUserQuestion**:

- **"Which projects should be imported?"** (header: "Import")
  - Options: "All projects", "Let me pick specific ones", "Show me the list first"
  - multiSelect: false

If the user picks specific ones, use another AskUserQuestion with multiSelect: true listing the top projects as options (up to 4, with Others available for custom input).

Suggest life names (lowercase, spaces to hyphens) and let the user confirm.

## Step 3: Check for existing lives

For each project being imported, check if `~/.claude-lives/{life_name}/memory.md` already exists.

If it does, use **AskUserQuestion** to warn and confirm:

- **"Life '{life_name}' already has memory data. Existing files will be backed up (.pre-migration). Continue?"** (header: "Overwrite")
  - Options: "Yes, back up and replace", "No, skip this life"
  - multiSelect: false

## Step 4: Run the migration

Run the migration script. Search for it in order:

1. `~/.claude/claude-lives-lib/claude_mem.py` (npx install location)
2. The plugin directory: look for a `migration/claude_mem.py` relative to any installed claude-lives plugin
3. Ask the user where they cloned/downloaded claude-lives

```bash
# Try the npx install location first
python3 ~/.claude/claude-lives-lib/claude_mem.py --db ~/.claude-mem/claude-mem.db --output ~/.claude-lives

# Or from plugin root (if installed via marketplace)
python3 <plugin_root>/migration/claude_mem.py --db ~/.claude-mem/claude-mem.db --output ~/.claude-lives
```

After running, verify that each life directory was created with the expected files:
- `~/.claude-lives/{life_name}/memory.md`
- `~/.claude-lives/{life_name}/handover.md`
- `~/.claude-lives/{life_name}/config.yaml`
- `~/.claude-lives/{life_name}/sessions/`
- `~/.claude-lives/{life_name}/archive/`

## Step 5: Connect life to directory

### Per-directory mode

The current directory IS the target. Create the `.claude-life` marker and inject memory here:

1. Create `.claude-life` in the current directory:
   ```yaml
   name: {life_name}
   created: {today YYYY-MM-DD}
   description: Migrated from claude-mem project "{project_name}"
   token_budget:
     life: 4000
     handover: 1500
   ```

2. Inject memory into the current directory's CLAUDE.md between markers:
   ```
   <!-- CLAUDE-LIVES:START:{life_name} -->
   ...memory content...
   <!-- CLAUDE-LIVES:END -->
   ```
   If no CLAUDE.md exists, create one with just the memory section.

3. Also create global memory if `~/.claude-lives/global/memory.md` doesn't exist yet.

### Bulk mode

For each imported life, use **AskUserQuestion**:

- **"Where should life '{life_name}' be connected?"** (header: "Directory")
  - Options: "Skip for now" (description: "Connect later by running /import-claude-mem from the project directory"), "Let me type the path"
  - multiSelect: false

If the user provides a directory path:
1. Verify the directory exists
2. Create `.claude-life` in that directory with the life name
3. Inject memory into the project's CLAUDE.md

## Step 6: Report

### Per-directory mode
```
Import complete!

  Imported: "my-research" → life "my-research"
  - 150 observations, 20 summaries
  - Memory: ~/.claude-lives/my-research/memory.md
  - Marker: ./.claude-life
  - CLAUDE.md updated with memory section

Next steps:
  - Run /resume to verify the memory looks right
  - Run /compact-memory if the migrated memory is too verbose
  - Run /memory-status to check token budgets
  - To import another project, cd there and run /import-claude-mem again
```

### Bulk mode
```
Migration complete!

Imported:
  my-research — 150 observations, 20 summaries → ~/.claude-lives/my-research/
  my-tutor — 120 observations, 15 summaries → ~/.claude-lives/my-tutor/
  (skipped: old-project)

Connected to directories:
  my-research → ~/projects/my-research/.claude-life
  my-tutor → ~/projects/my-tutor/.claude-life
  work — not connected (run /import-claude-mem from the project directory)

Migration report: ~/.claude-lives/migration-report.md

Next steps:
  1. cd to each project directory and run /resume to verify
  2. Run /compact-memory if migrated memory is too verbose
  3. Run /memory-status to check token budgets
```

## Arguments

If the user passes arguments, handle them:
- `--all` — Bulk mode: import all projects, ask for directory mappings
- `--db /path/to/db` — Use a custom database path instead of `~/.claude-mem/claude-mem.db`
- `--dry-run` — Show what would be imported without making changes

$ARGUMENTS
