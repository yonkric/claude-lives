---
description: Sync life memory to git (commit and push ~/.claude-lives/)
---

Sync all life memories to git for cross-machine access.

## Steps

1. Check if `~/.claude-lives/` is a git repository. If not, offer to initialize it:
   ```bash
   cd ~/.claude-lives && git init && git add -A && git commit -m "init: claude-lives memory store"
   ```

2. If it is a git repo, check for changes:
   ```bash
   cd ~/.claude-lives && git status --porcelain
   ```

3. If there are changes, stage tracked files and new memory files, then commit and push:
   ```bash
   cd ~/.claude-lives && git add -u && git add '*.md' '*.yaml' && git commit -m "sync: {date}" && git push
   ```
   Note: We use `git add -u` + explicit patterns instead of `git add -A` to avoid accidentally staging sensitive files. Review your `~/.claude-lives/.gitignore` to ensure it covers any files you don't want committed.
   If no remote is configured, tell the user to add one:
   "No git remote configured. Add one with: `cd ~/.claude-lives && git remote add origin <url>`"

4. If no changes, tell the user: "Memory store is already up to date."

5. Report what was synced: number of files changed, lives affected.

$ARGUMENTS
