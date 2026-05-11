# claude-lives

Claude Code plugin for life-context isolation. Pure markdown + bash + slash commands.

## Project Structure

```
commands/        — Slash command markdown files (the main interface)
hooks/           — Shell scripts registered as Claude Code hooks (Stop + PostToolUse)
lib/             — Shared bash utilities (detection, token counting, snapshots)
templates/       — File templates for life creation
migration/       — claude-mem migration script (Python)
.claude-plugin/  — Plugin manifest and marketplace descriptor
tests/           — Test scripts
docs/            — Design docs, plan, test reports
```

## Key Architecture Decisions

- Life detection uses `.claude-life` marker files (NOT CLAUDE.md frontmatter)
- Memory injection goes INTO CLAUDE.md between `<!-- CLAUDE-LIVES:START -->` / `<!-- CLAUDE-LIVES:END -->` markers
- Slash commands are the primary interface — Claude does the intelligence work
- Token counting is approximate (4 chars ≈ 1 token) — soft budget
- PostToolUse hook counts tool calls; CLAUDE.md instruction triggers mid-session snapshots to disk every ~20 calls to preserve context across auto-compaction
- No MCP server, no external services, no Python for core features
- Hooks are installed to `~/.claude/claude-lives-lib/hooks/` so they work after npx cleanup

## Development Commands

```bash
# Run all tests
bash tests/run_all.sh

# Test life detection
bash lib/detect_life.sh

# Count tokens in a file
bash lib/token_count.sh <file>
```

## File Conventions

- Slash commands: lowercase with hyphens (e.g., `save-session.md`)
- Shell scripts: snake_case (e.g., `detect_life.sh`)
- All shell scripts must be POSIX-compatible or explicitly require bash
- Templates use `{{placeholder}}` syntax for substitution
