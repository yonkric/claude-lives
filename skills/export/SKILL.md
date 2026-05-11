---
description: Export a life (or project) as a portable tarball for use on another machine
---

Export the current life or project as a self-contained `.tar.gz` archive that can be imported on another machine with `/import-life`.

## Arguments

Optional: a path where the tarball should be written. Defaults to `~/{name}.claude-life.tar.gz`.

If the user passes `--include-life-context`, also bundle the parent life-level memory when exporting a project from a workspace life.

## Step 1: Detect What to Export

Find the current life by walking up from the working directory looking for `.claude-life`. Read it to get the life name and type.

If no life is found, tell the user: "No life detected. Nothing to export." and stop.

**Determine export scope:**

- **Flat life**: export the entire life storage at `~/.claude-lives/{life}/`
- **Workspace life, at the root**: ask the user whether to export the whole workspace or a specific project:
  - Use AskUserQuestion with header "Scope":
    - "Export entire workspace" (description: "Bundles life-level memory + all projects")
    - "Export a specific project" (description: "Bundles only one project's memory. On import, it becomes a standalone flat life")
  - If "specific project": list subdirectories of the workspace and ask which one (or accept a name from the arguments)
- **Workspace life, inside a project directory**: export that project. The project name is the first directory component under the life root.

Store the determined scope: `life_name`, `project_name` (or null for whole-life export), `export_type` (one of: `flat`, `workspace`, `project`).

## Step 2: Gather Files

Determine the storage directory to bundle:

- **Flat life or whole workspace**: `~/.claude-lives/{life}/`
- **Project from workspace**: `~/.claude-lives/{life}/projects/{project}/`

Verify the storage directory exists and has content. If empty or missing, tell the user: "No saved memory found for this life/project. Run /save-session first." and stop.

**Build the file list:**

1. The storage directory contents (memory.md, handover.md, config.yaml, sessions/, archive/)
2. The `.claude-life` marker file from the source directory (for flat lives and whole workspaces)
3. If `--include-life-context` was passed AND exporting a project: also include `~/.claude-lives/{life}/memory.md` as `_parent_memory.md` in the archive

**Exclude from the archive:**
- `.session-snapshots/` directories (transient)
- `.last-saved` files (transient)
- `.last-session-meta.json` (transient)
- Any `.lock` files

## Step 3: Create Export Manifest

Write a temporary `_export.json` manifest that will be included in the tarball:

```json
{
  "format": "claude-lives-export",
  "version": 1,
  "exported_at": "{ISO 8601 timestamp}",
  "source_machine": "{hostname}",
  "export_type": "{flat|workspace|project}",
  "life_name": "{life_name}",
  "project_name": "{project_name or null}",
  "parent_life_name": "{parent life name, only for project exports}",
  "includes_life_context": {true|false},
  "claude_lives_version": "0.2.1"
}
```

Use `hostname` command for source_machine. Use Node.js for JSON generation:

```bash
node -e "
  const m = {
    format: 'claude-lives-export',
    version: 1,
    exported_at: new Date().toISOString(),
    source_machine: require('os').hostname(),
    export_type: process.argv[1],
    life_name: process.argv[2],
    project_name: process.argv[3] || null,
    parent_life_name: process.argv[4] || null,
    includes_life_context: process.argv[5] === 'true',
    claude_lives_version: '0.2.1'
  };
  process.stdout.write(JSON.stringify(m, null, 2));
" "{export_type}" "{life_name}" "{project_name}" "{parent_life}" "{includes_life_context}" > /tmp/_export.json
```

## Step 4: Create the Tarball

Build the archive. The tarball's internal structure should be flat under a single root directory named after the export:

```
{name}/
  _export.json          ← manifest
  memory.md             ← life or project memory
  handover.md           ← handover notes
  config.yaml           ← token budgets etc (if exists)
  sessions/             ← session logs
  archive/              ← archived sessions (if exists)
  _parent_memory.md     ← parent life memory (only if --include-life-context)
  .claude-life          ← marker file (only for flat/workspace exports)
```

For **flat life** exports, `{name}` is the life name.
For **project** exports, `{name}` is the project name.
For **workspace** exports, `{name}` is the life name, and projects are nested under `projects/`.

Use a temporary staging directory to assemble the archive:

```bash
STAGE=$(mktemp -d)
EXPORT_DIR="$STAGE/{name}"
mkdir -p "$EXPORT_DIR"

# Copy storage
cp -r ~/.claude-lives/{life}/* "$EXPORT_DIR/"
# Or for project: cp -r ~/.claude-lives/{life}/projects/{project}/* "$EXPORT_DIR/"

# Remove transient files
rm -rf "$EXPORT_DIR/.session-snapshots" "$EXPORT_DIR/.last-saved" "$EXPORT_DIR/.last-session-meta.json"
find "$EXPORT_DIR" -name "*.lock" -delete

# Add manifest
cp /tmp/_export.json "$EXPORT_DIR/_export.json"

# Add .claude-life marker (for flat/workspace)
# cp {life_root}/.claude-life "$EXPORT_DIR/.claude-life"

# If --include-life-context for project export:
# cp ~/.claude-lives/{life}/memory.md "$EXPORT_DIR/_parent_memory.md"

# Create tarball
OUTPUT="${output_path:-$HOME/{name}.claude-life.tar.gz}"
tar -czf "$OUTPUT" -C "$STAGE" "{name}"

# Clean up
rm -rf "$STAGE" /tmp/_export.json
```

## Step 5: Confirm

Report to the user:

- Exported: `{life_name}` (type: {export_type})
- If project export: "Project `{project_name}` from workspace `{life_name}`"
- Archive: `{output_path}`
- Size: `{file size}`
- Contents: {count} session logs, memory, handover
- If `--include-life-context`: "Includes parent life memory"

Then tell the user:

```
To import on another machine:
  1. Copy {filename} to the target machine
  2. Run: /import-life {path_to_tarball}
```

$ARGUMENTS
