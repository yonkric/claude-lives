---
description: Import a life from a portable tarball exported by /export
---

Import a `.claude-life.tar.gz` archive (created by `/export`) into the current machine as a new life.

## Arguments

Optional: path to the `.claude-life.tar.gz` file. If omitted, auto-find searches common locations.

Optional flags:
- `--name {name}`: override the life name (default: use the name from the export manifest)
- `--here`: also place the `.claude-life` marker in the current directory (making the current directory the life root). Without this flag, only the memory store is imported — you can place the marker later with `/new-life`.

## Step 1: Find and Validate the Archive

### Auto-find (when no path argument given)

Search these directories in order for files matching `*.claude-life.tar.gz`:

```bash
SEARCH_DIRS="$HOME $HOME/Downloads $HOME/Desktop $(pwd)"
FOUND=()
for dir in $SEARCH_DIRS; do
  if [ -d "$dir" ]; then
    while IFS= read -r f; do
      FOUND+=("$f")
    done < <(find "$dir" -maxdepth 1 -name "*.claude-life.tar.gz" -type f 2>/dev/null)
  fi
done
```

Deduplicate results (a file in `$HOME` may also match `$(pwd)` if you're in `$HOME`).

**If no files found:** Tell the user: "No `.claude-life.tar.gz` files found in ~/, ~/Downloads/, ~/Desktop/, or the current directory. Either pass the path explicitly (`/import-life /path/to/file.tar.gz`) or move the tarball to one of those locations." and stop.

**If exactly one file found:** Use it automatically after confirming with the user: "Found export archive: `{path}` — importing this file."

**If multiple files found:** Use AskUserQuestion with header "Archive" listing each file as an option (label: filename, description: full path + file size + modification date). Include multiSelect: false.

### Validate

Verify the file exists and is a valid gzip tarball:

```bash
file "{path}" | grep -q "gzip"
```

If not a valid archive, tell the user: "Not a valid claude-lives export archive." and stop.

Extract to a temporary directory and look for the manifest:

```bash
STAGE=$(mktemp -d)
tar -xzf "{path}" -C "$STAGE"
```

Find `_export.json` in the extracted contents:

```bash
MANIFEST=$(find "$STAGE" -name "_export.json" -maxdepth 2 | head -1)
```

If no manifest found, tell the user: "This archive doesn't contain a claude-lives export manifest. Was it created with /export?" and stop.

Read the manifest using Node.js:

```bash
node -e "const m = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); console.log(JSON.stringify(m));" "$MANIFEST"
```

Validate `format` is `"claude-lives-export"` and `version` is `1`. If not, tell the user the format is unrecognized and stop.

## Step 2: Determine Life Name and Check Conflicts

The life name comes from (in priority order):
1. `--name` argument if provided
2. `project_name` from manifest (for project exports)
3. `life_name` from manifest (for flat/workspace exports)

Validate the name matches `^[a-zA-Z0-9_-]+$`. If not, ask the user for a valid name.

Check if `~/.claude-lives/{name}/` already exists. If it does, ask the user:

Use AskUserQuestion with header "Conflict":
- "Overwrite existing life" (description: "Replaces all memory, handover, and sessions for '{name}'")
- "Import with a different name" (description: "You'll be prompted for a new name")
- "Cancel" (description: "Abort import")
- multiSelect: false

If "different name": ask for a new name via AskUserQuestion (freeform, header "Name").
If "Cancel": clean up temp dir and stop.

## Step 3: Import Memory Store

Determine the extracted content directory (the single directory inside `$STAGE`):

```bash
CONTENT_DIR=$(find "$STAGE" -mindepth 1 -maxdepth 1 -type d | head -1)
```

Create the target life storage:

```bash
LIVES_DIR="${CLAUDE_LIVES_DIR:-$HOME/.claude-lives}"
TARGET="$LIVES_DIR/{name}"
mkdir -p "$TARGET/sessions" "$TARGET/archive"
```

Copy the memory files:

```bash
# Core files
cp "$CONTENT_DIR/memory.md" "$TARGET/memory.md" 2>/dev/null || true
cp "$CONTENT_DIR/handover.md" "$TARGET/handover.md" 2>/dev/null || true
cp "$CONTENT_DIR/config.yaml" "$TARGET/config.yaml" 2>/dev/null || true

# Sessions
if [ -d "$CONTENT_DIR/sessions" ]; then
  cp -r "$CONTENT_DIR/sessions/"* "$TARGET/sessions/" 2>/dev/null || true
fi

# Archive
if [ -d "$CONTENT_DIR/archive" ]; then
  cp -r "$CONTENT_DIR/archive/"* "$TARGET/archive/" 2>/dev/null || true
fi
```

**If the export was a project from a workspace** (`export_type` is `"project"`):
- The memory.md frontmatter may reference the old life/project names. Update the frontmatter:
  - Change `life: {old_life}` → `life: {name}`
  - Remove `project: {old_project}` line if present (it's now a standalone life, not a project)
- Same for handover.md frontmatter.

Use Node.js to patch the frontmatter:

```bash
node -e "
  const fs = require('fs');
  const file = process.argv[1];
  const newName = process.argv[2];
  let content = fs.readFileSync(file, 'utf8');
  content = content.replace(/^life:.*$/m, 'life: ' + newName);
  content = content.replace(/^project:.*\n/m, '');
  fs.writeFileSync(file, content);
" "$TARGET/memory.md" "{name}"
```

Do the same for handover.md.

**If `_parent_memory.md` exists** (from `--include-life-context`):
- Copy it as `$TARGET/_parent_context.md` — it's reference material from the original parent life, not the active memory. It won't be actively maintained but provides useful context.

**For workspace exports** (`export_type` is `"workspace"`):
- The `projects/` subdirectory is preserved as-is inside `$TARGET/projects/`
- Copy: `cp -r "$CONTENT_DIR/projects" "$TARGET/projects"` (if it exists)

## Step 4: Place .claude-life Marker (if --here)

If `--here` was passed, create a `.claude-life` marker in the current directory:

```yaml
name: {name}
created: {today YYYY-MM-DD}
description: Imported from {source_machine} ({exported_at date})
type: {flat for project/flat imports, workspace for workspace imports}
token_budget:
  life: 4000
  handover: 1500
```

Also add `.claude-life` to `.gitignore` if the current directory is a git repo (same logic as /new-life Step 2a-bis).

If `--here` was NOT passed, tell the user: "Memory imported. To activate this life in a directory, either run `/new-life` there or create a `.claude-life` marker manually."

## Step 5: Create Global Memory (if needed)

If `~/.claude-lives/global/memory.md` doesn't exist, create it with default content (same as /new-life Step 2c).

## Step 6: Inject into CLAUDE.md (if --here)

If `--here` was passed and a CLAUDE.md exists (or was created), inject the progressive disclosure index between `<!-- CLAUDE-LIVES:START:{name} -->` and `<!-- CLAUDE-LIVES:END -->` markers, same format as /save-session Step 6.

Read the imported memory.md and handover.md to populate the index fields.

If no CLAUDE.md exists and `--here` was passed, create one with just the life section.

## Step 7: Clean Up and Confirm

```bash
rm -rf "$STAGE"
```

Report to the user:

- Imported life: `{name}` (from: {source_machine}, exported: {date})
- Original export type: {flat|workspace|project}
- If project→flat conversion: "Converted project `{project_name}` (from workspace `{parent_life}`) into standalone life `{name}`"
- Memory store at: `~/.claude-lives/{name}/`
- Sessions imported: {count}
- If `--here`: "Life marker placed at `.claude-life`, CLAUDE.md updated"
- If not `--here`: "Run `/new-life` in your project directory to activate, or pass `--here` to place the marker in the current directory"
- If `_parent_context.md` was included: "Parent life context saved as `_parent_context.md` in the memory store for reference"

$ARGUMENTS
