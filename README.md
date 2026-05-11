# claude-lives

Memory isolation for Claude Code. Separate your work, research, and side projects into fully isolated "lives" that remember what you were doing.

## The Problem

Claude Code is stateless. Every `/clear` or new session starts fresh. If you work across multiple contexts (job, PhD, freelance), existing memory tools dump everything into one pool — work context leaks into research sessions and vice versa.

## The Solution

claude-lives ties memory to **directories** using a three-layer model:

| Layer | Scope | Example |
|-------|-------|---------|
| **Global** | All lives | Communication style, tool preferences |
| **Life** | One context (work, PhD, freelance) | Team norms, shared constraints, identity |
| **Project** | One repo/project within a life | Current focus, handover notes, session logs |

`cd ~/phd` = PhD mode. `cd ~/work/project-a` = work mode, project-a context. No switching, no manual maintenance.

**Flat lives** (like your PhD) are a single project — the life IS the project. **Workspace lives** (like your work folder) contain multiple projects that each get their own context while inheriting the life-level identity and preferences.

Memory persists across `/clear` because it lives in CLAUDE.md, which Claude Code reads automatically on every session start.

## Quick Start

### As a Claude Code Plugin (recommended)

```
/plugin marketplace add yonkric/claude-lives
/plugin install claude-lives@claude-lives
```

### Via npx

```bash
npx claude-lives
```

### Manual Install

```bash
git clone https://github.com/yonkric/claude-lives
cd claude-lives
./install.sh
```

All methods install 13 slash commands and two hooks (Stop + PostToolUse). The npx and manual methods also create the `~/.claude-lives/` memory store upfront; the plugin method creates it when you first run `/new-life`. Run `./uninstall.sh` to remove (your memory data is preserved unless you pass `--delete-data`).

**Upgrading?** Just re-run the same install command. Skills and hooks are replaced with the latest version; your memory data at `~/.claude-lives/` is never touched.

## Getting Started

Go to any project directory and create a new life:

```bash
cd ~/my-project
```
```
/new-life
```

Claude interviews you about the project (what it's for, what tools you use, your preferences) and sets everything up. Do this once per project directory.

## Daily Workflow

### The Minimalist Way (recommended)

Most users only need one command. Work normally, then when you're done:

```
/fresh
```
Then type `/clear` when prompted. That's it. Claude saves your session, updates memory, and you start clean next time with full context.

Your CLAUDE.md already has your project context, so the next time you run `claude` in this directory, Claude knows who you are, what you were working on, and what's next — no `/resume` needed for basic continuity.

### The Full Workflow

If you want more control:

```
/save-session        # Save at any point (not just when ending)
/resume              # See full handover details (richer than the CLAUDE.md index)
/checkpoint          # Mid-session snapshot to preserve context before compaction
/search <query>      # Find past decisions, code references, session notes
/timeline            # See narrative project history grouped by week
/memory-status       # Check token usage and session economics
/compact-memory      # Compress when memory is over 80% budget
```

### How auto-save works (and its limits)

claude-lives includes a **Session Protocol** that tells Claude to proactively run `/save-session` before ending substantial sessions. This works well when Claude finishes a task and you have a natural conversation end. However:

- **If you close the terminal**, Claude can't run commands — the stop hook writes metadata (what happened, how many files changed) but doesn't save full memory. Use `/fresh` before closing to be safe.
- **Mid-session snapshots**: A PostToolUse hook counts tool calls. Every ~20 tool calls, Claude writes a brief snapshot to disk. This means even if you close the terminal, partial work is preserved. `/resume` will detect and offer to recover these snapshots.
- **Long sessions**: During long sessions where Claude Code auto-compacts the conversation, early work would normally be lost. The snapshot system captures incremental summaries before compaction happens, so `/save-session` can produce a comprehensive session log covering the full session.
- **Auto-resume is automatic.** CLAUDE.md contains a ~500-token progressive index that Claude reads on every session start. This gives basic continuity without any user action. `/resume` is for when you want the full handover.
- **Stale detection**: If a previous substantial session wasn't saved, Claude detects this on next start and alerts you.

### What happens on `/clear`?

When you `/clear`, Claude's conversation is wiped — but CLAUDE.md is not. Your life memory and handover notes survive because they're injected between marker comments. Claude reads CLAUDE.md on every session start, so your context persists.

### When memory gets large

After many sessions, memory approaches its token budget. `/save-session` warns you at 80%. When that happens:

```
/compact-memory
```

This deduplicates facts, archives old session logs, and decays stale information.

## All Commands

| Command | What it does |
|---------|-------------|
| `/new-life` | Set up a new life in the current directory (interactive interview) |
| `/fresh` | Save session + prepare for `/clear` — single command to switch tasks |
| `/save-session` | Save current session: write log, update handover, refresh CLAUDE.md |
| `/resume` | Show handover notes and detect unsaved previous sessions |
| `/search <query>` | Full-text search across sessions, memory, and handover (`--all` for cross-life) |
| `/timeline` | Narrative project history from session logs (`--weeks N`, `--format brief`) |
| `/memory-status` | Token usage, session history, freshness, and token economics |
| `/compact-memory` | Compress memory: deduplicate, archive old sessions, decay stale facts |
| `/borrow <life>` | Read-only peek at another life's memory (doesn't modify anything) |
| `/sync` | Git commit and push `~/.claude-lives/` for cross-machine sync |
| `/checkpoint` | Save a mid-session snapshot to preserve context before auto-compaction |
| `/import-claude-mem` | Import from claude-mem database (see [Migrating from claude-mem](#migrating-from-claude-mem)) |
| `/cl-inject` | (Internal) Manually refresh the CLAUDE.md memory section |

## How It Works

1. A `.claude-life` marker file in a directory tells claude-lives which life this is and its type (`flat` or `workspace`)
2. Memory is stored at `~/.claude-lives/{life-name}/` (memory.md, handover.md, session logs)
3. For **workspace** lives, each child directory is a separate project with its own memory at `~/.claude-lives/{life}/projects/{project}/` — auto-initialized on first use, no setup needed
4. On `/save-session`, Claude writes a session summary, updates handover notes, and injects a **compact index** into CLAUDE.md between `<!-- CLAUDE-LIVES:START:{life} -->` / `<!-- CLAUDE-LIVES:END -->` markers
5. CLAUDE.md is read automatically by Claude Code on every session start — this is how memory survives `/clear`
6. A Stop hook writes a `.last-session` timestamp and `.last-session-meta.json` (message count, files modified, significance flag) for stale session detection
7. A PostToolUse hook silently counts tool calls. The CLAUDE.md progressive block includes a **Session Protocol** that tells Claude to write mid-session snapshots to disk every ~20 tool calls, preserving early work before auto-compaction erases it. `/save-session` merges these disk snapshots with current context for comprehensive session logs
8. The Session Protocol also tells Claude to auto-save before ending substantial sessions and check for unsaved work on start
9. Global preferences at `~/.claude-lives/global/memory.md` are shared across all lives

### Flat vs Workspace Lives

| | Flat Life | Workspace Life |
|---|-----------|---------------|
| **Use when** | This directory is one project (PhD, a single repo) | This directory contains multiple projects |
| **Example** | `~/phd/.claude-life` | `~/work/.claude-life` |
| **Projects** | None — the life IS the project | Auto-detected from child directories |
| **Setup** | `/new-life` → answer "one project" | `/new-life` → answer "workspace with multiple projects" |
| **Per-project context** | N/A | Each project gets its own handover, sessions, focus |
| **Inherited context** | N/A | Life identity + preferences flow into every project |

## Token Optimization

claude-lives uses three techniques to minimize token usage:

### 1. Progressive Disclosure

Instead of injecting full memory into CLAUDE.md (~6,500 tokens), we inject a **compact index** (~500 tokens) that contains:
- Identity and current focus (1 line each)
- Last session context (what was happening, next steps)
- Top 5 key facts
- File paths to full memory files

Claude reads the full files on demand when it needs more detail. This is a ~10x reduction in per-session context cost.

### 2. Telegraphic Compression

All memory content is written in compressed style:
- No articles (a, an, the), no filler verbs
- Short phrases over sentences: "PyTorch 2.1, CUDA 12.2" not "We are using PyTorch version 2.1 with CUDA 12.2"
- One fact per line, dash-prefix format
- Abbreviations when clear: "ch4" not "chapter 4"

This achieves ~40-60% reduction on stored memory content.

### 3. Relevance Decay

`/compact-memory` scores facts by recency and actionability. Facts not referenced in the last 10 sessions are archived or removed. Completed tasks are cleaned out. This prevents unbounded memory growth.

### Token Budgets

Full memory files are kept within soft budgets:

| Layer | Default Budget | In CLAUDE.md |
|-------|---------------|-------------|
| Global preferences | 1,000 tokens | ~3 lines |
| Life memory | 4,000 tokens | ~3-5 key facts |
| Project memory (workspace only) | 3,000 tokens | ~5 project facts |
| Handover notes | 1,500 tokens | ~3 lines |
| **CLAUDE.md index** | — | **~500-600 tokens** |

Budgets are configurable per-life in `~/.claude-lives/{life}/config.yaml`.

### Security

Memory files are scanned for prompt injection patterns (role injection, instruction overrides, delimiter injection) before being written to CLAUDE.md. Warnings are logged if suspicious patterns are detected. Always review migrated or imported memory content.

### Directory Structure

```
~/.claude-lives/
├── global/
│   ├── memory.md          # Shared preferences across all lives
│   └── config.yaml
├── .snapshot-dir.*         # Sentinel files for active snapshot sessions
├── my-research/            # Flat life (life = project)
│   ├── memory.md
│   ├── handover.md
│   ├── config.yaml
│   ├── sessions/          # Session logs (YYYY-MM-DD-NNN.md)
│   ├── archive/           # Compressed monthly archives
│   └── .session-snapshots/ # Mid-session snapshots (temporary, cleaned up on save)
│       ├── counter         # Tool-call counter (integer)
│       ├── snapshots.md    # Incremental summaries
│       └── session-id      # Session timestamp + cached life/project
├── work/                  # Workspace life (contains projects)
│   ├── memory.md          # Life-level identity & shared context
│   ├── config.yaml
│   └── projects/
│       ├── project-a/     # Auto-initialized on first use
│       │   ├── memory.md
│       │   ├── handover.md
│       │   ├── sessions/
│       │   └── archive/
│       └── project-b/
│           └── ...
└── migration-report.md    # Generated after /import-claude-mem
```

In each life directory:
```
~/my-research/
├── .claude-life           # Marker file (name: my-research, type: flat)
├── CLAUDE.md              # Memory injected between markers here
└── ...your project files

~/work/
├── .claude-life           # Marker file (name: work, type: workspace)
├── project-a/
│   ├── CLAUDE.md          # Project-specific memory injected here
│   └── ...project files
└── project-b/
    └── ...
```

## Syncing Across Machines

`~/.claude-lives/` is initialized as a git repo. To sync:

```
/sync
```

This commits and pushes your memory store. On another machine, clone the repo to `~/.claude-lives/` and run the installer.

## Known Limitations

- **Auto-save is best-effort.** The Session Protocol is a CLAUDE.md instruction, not a guaranteed hook. If you close the terminal without `/fresh`, memory is not saved — but mid-session snapshots on disk are preserved. The stop hook captures metadata (significance flag) and preserves unsaved snapshots for recovery via `/resume`.
- **No auto-compact.** Memory grows with each session. You'll need to run `/compact-memory` manually when `/save-session` warns about budget usage (planned for auto-compact in a future release).
- **Single-user only.** Memory is per-machine at `~/.claude-lives/`. No team sharing, no shared memory layer. In shared repos, each developer's CLAUDE.md injection would cause merge conflicts.
- **Full-text search only.** `/search` uses `rg`/`grep`, not semantic/vector search. Good for exact terms, less useful for conceptual queries.
- **Claude Code only.** Does not work with Cursor, Windsurf, Gemini CLI, or other AI coding tools.

## Roadmap

| Version | Focus | Key Changes |
|---------|-------|-------------|
| **v0.3** | Power features | Session tagging, /forget, /list-lives dashboard, /sync conflict handling |
| **v1.0** | Team support | Gitignored injection target, CLAUDE_LIVES_READONLY mode, team-memory.md layer, /share command |

## Additional Information

### Migrating from claude-mem

If you're coming from [claude-mem](https://github.com/thedotmack/claude-mem) or another Claude Code memory tool, **disable it first** to avoid conflicts (duplicate context injection, fighting over CLAUDE.md).

Then import your data using `/import-claude-mem`:

**Per-directory (recommended):**
```bash
cd ~/projects/my-research
```
```
/import-claude-mem
```

claude-lives auto-detects the matching claude-mem project by directory name. Repeat for each project directory.

**Bulk import:**
```
/import-claude-mem --all
```

**Options:**
- `--dry-run` — preview what would be imported without making changes
- `--db /path/to/db` — use a custom database path (default: `~/.claude-mem/claude-mem.db`)
- `--all` — bulk import all projects at once

After importing, remove claude-mem's hooks from `~/.claude/settings.json` and rename or remove `~/.claude-mem/` to prevent re-activation.

### Conflict with other memory tools

Running multiple memory systems simultaneously causes conflicts — duplicate context injection, fighting over CLAUDE.md, bloated token usage, and unpredictable behavior. Uninstall or disable other memory tools before using claude-lives.

## Requirements

- Claude Code (Node.js is used internally for hook registration)
- bash (4.0+)
- git (for /sync)
- Python 3.8+ (optional — only needed for `/import-claude-mem` migration from claude-mem)

## License

[MIT](LICENSE)
