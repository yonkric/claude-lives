# claude-lives

Claude Code plugin for life-context isolation. Pure markdown + bash + slash commands.

## Project Structure

```
skills/          — Skill directories (each has SKILL.md — the main interface)
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
- Slash commands are the primary interface — Claude does the intelligence work
- Token counting is approximate (4 chars ≈ 1 token) — soft budget
- PostToolUse hook counts tool calls; CLAUDE.md instruction triggers mid-session snapshots to disk every ~20 calls to preserve context across auto-compaction
- No MCP server, no external services, no Python for core features (Python only for optional claude-mem migration)
- Hooks work via two paths: plugin `hooks/hooks.json` (marketplace installs) and `~/.claude/claude-lives-lib/hooks/` (npx installs)
- JSON manipulation uses Node.js (guaranteed by Claude Code) instead of Python

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

- Skills: lowercase with hyphens, each in its own directory (e.g., `skills/save-session/SKILL.md`)
- Shell scripts: snake_case (e.g., `detect_life.sh`)
- All shell scripts must be POSIX-compatible or explicitly require bash
- Templates use `{{placeholder}}` syntax for substitution

<!-- CLAUDE-LIVES:START:claude-lives -->
## Life: claude-lives

**Identity:** Claude Code plugin for life-context isolation. Pure markdown + bash + slash commands. Published at github.com/yonkric/claude-lives.
**Focus:** v0.3.0 — added /export and /import-life for portable cross-machine workflows.
**Last session:** 2026-05-11
**Was doing:** Implemented /export and /import-life skills. Version bumped to 0.3.0.
**Next:** - npm publish v0.3.0
- Test export/import workflow (local → VM)
- Implement claude-code native memory backend (refactor commands to use ~/.claude/projects/<path>/memory/)

### Global
These preferences apply across all lives.

### Full Memory (read when needed)
- Life memory: `/Users/Lenovo/.claude-lives/claude-lives/memory.md`
- Handover: `/Users/Lenovo/.claude-lives/claude-lives/handover.md`
- Global: `/Users/Lenovo/.claude-lives/global/memory.md`
- Sessions: `/Users/Lenovo/.claude-lives/claude-lives/sessions/`
- Session meta: `/Users/Lenovo/.claude-lives/claude-lives/.last-session-meta.json`

### Session Protocol
- **On start**: Read `/Users/Lenovo/.claude-lives/claude-lives/.last-session-meta.json` — if `significant: true` and no `.last-saved` file is newer, previous session may be unsaved. Note this briefly.
- **Mid-session snapshots**: A tool-call counter increments at `/Users/Lenovo/.claude-lives/claude-lives/.session-snapshots/counter`. When you read or write files and notice the counter exceeds 20, write a brief incremental summary (3-6 bullets, telegraphic) to `/Users/Lenovo/.claude-lives/claude-lives/.session-snapshots/snapshots.md` using the format `<!-- snapshot:N t:{ISO8601} tools:{counter} -->\n## Snapshot N\n- bullet`, then write `0` to the counter file. This preserves early work before auto-compaction erases it.
- **Before ending**: If you modified files, made key decisions, or learned important context — run /save-session before your final response. Also trigger on closing phrases (goodbye, thanks, done, that's all). Skip only for single-question Q&A with no file changes.

<!-- CLAUDE-LIVES:END -->
