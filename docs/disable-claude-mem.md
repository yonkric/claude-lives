# Disabling claude-mem

claude-mem and claude-lives both manage memory for Claude Code. Running them simultaneously causes conflicts: duplicate context injection, fighting over CLAUDE.md, bloated token usage, and unpredictable behavior. Disable claude-mem before using claude-lives.

## Step 1: Import your data first

Before disabling, import your claude-mem observations into claude-lives so nothing is lost.

**Per-directory (recommended):**

```bash
cd ~/your-project
```
```
/import-claude-mem
```

Repeat for each project directory. claude-lives auto-detects the matching claude-mem project by directory name.

**Bulk import:**

```
/import-claude-mem --all
```

Use `--dry-run` to preview what would be imported before committing.

## Step 2: Disable the plugin

Open `~/.claude/settings.json` and find the `enabledPlugins` section:

```json
"enabledPlugins": {
    "claude-mem@thedotmack": true,
    ...
}
```

Change `true` to `false`:

```json
"enabledPlugins": {
    "claude-mem@thedotmack": false,
    ...
}
```

Save the file. This prevents claude-mem from loading on the next Claude Code session.

## Step 3: Stop running processes

claude-mem runs a background daemon worker and MCP servers. Stop them:

```bash
# Find claude-mem processes
ps aux | grep claude-mem | grep -v grep

# Kill the daemon worker (the main long-running process)
pkill -f "claude-mem.*worker-service"

# Kill the Chroma vector DB process
pkill -f "chroma-mcp.*claude-mem"
```

These processes will not restart since the plugin is disabled.

## Step 4: Rename the data directory (optional)

To prevent accidental re-activation, rename the data directory:

```bash
mv ~/.claude-mem ~/.claude-mem-backup
```

Your claude-mem database (`claude-mem.db`), Chroma embeddings, and logs are preserved in the backup. You can delete it later once you've confirmed claude-lives has all your data.

## Verifying it worked

Start a new Claude Code session. You should NOT see:
- `$CMEM` context block in the session start
- `mcp__plugin_claude-mem_*` tools available
- claude-mem worker processes running

You SHOULD see:
- claude-lives memory in CLAUDE.md (after running `/new-life` or `/import-claude-mem`)
- claude-lives slash commands available (`/save-session`, `/resume`, etc.)

## Re-enabling claude-mem

If you need to go back, reverse the steps:

1. Rename the backup back: `mv ~/.claude-mem-backup ~/.claude-mem`
2. Set `"claude-mem@thedotmack": true` in `~/.claude/settings.json`
3. Restart Claude Code — the daemon starts automatically

## Differences from claude-mem

| Feature | claude-mem | claude-lives |
|---------|-----------|-------------|
| Memory scope | Per-project (auto-detected) | Per-directory (explicit `.claude-life` marker) |
| Storage | SQLite + Chroma vectors | Markdown files in `~/.claude-lives/` |
| Context injection | MCP tools inject observations at session start | CLAUDE.md injection (survives `/clear`) |
| Token usage | ~39K+ tokens of context per session | ~500 tokens (progressive disclosure index) |
| Cross-project isolation | Soft (project name matching) | Hard (directory-based, no leakage) |
| Memory compression | Summarization via LLM | Telegraphic style + relevance decay |
| Sync | Not built-in | Git-based (`/sync`) |
