# Changelog

All notable changes to claude-lives are documented here.

## [0.2.0] — 2026-05-11

### Plugin Architecture Fixes

**Problem:** Plugin marketplace installs (`/plugin marketplace add`) only loaded skills but not hooks, because `plugin.json` didn't declare the hooks directory. Users on the marketplace path had no session tracking or auto-save metadata.

**Problem:** Core functionality (stop hook, installer, uninstaller) required Python 3.8+ for JSON parsing and hook registration. This contradicted the "no Python for core features" philosophy and added an unnecessary dependency.

**Fixes:**
- Added `"hooks": "./hooks/"` to `plugin.json` — marketplace installs now get both hooks automatically
- Replaced Python JSON parsing in `stop_hook.sh` with pure bash (`grep`/`sed`)
- Replaced Python JSON manipulation in `install.sh` and `uninstall.sh` with Node.js (guaranteed available — Claude Code requires it)
- Fixed heredoc date expansion bug in `install.sh` (was using single-quoted heredoc then patching with `sed`)
- Python 3.8+ is now optional — only needed for `/import-claude-mem` migration

**Upgrade support:**
- Installer now detects previous version via `~/.claude/claude-lives-lib/.version` marker
- Shows "Upgrading X → Y" messaging on re-install
- Skills, hooks, and lib scripts are always replaced with latest
- Memory data at `~/.claude-lives/` is never modified during upgrades

**Other:**
- `/import-claude-mem` now searches multiple locations for the migration script (npx path, plugin root)
- Updated README requirements, roadmap, and upgrade instructions
- Version bumped from 0.1.1 to 0.2.0 across plugin.json, marketplace.json, and package.json
- Tests: 329/329 passing

### Skills Migration (v0.1.1)

Migrated from legacy `commands/` to modern `skills/` directory format.

- All 13 slash commands moved from `commands/*.md` to `skills/*/SKILL.md`
- Installer, uninstaller, plugin manifest, and all 11 test files updated
- `plugin.json` now uses `"skills": ["./skills/"]` instead of `"commands"`
- Installer cleans up legacy `~/.claude/commands/` entries from previous installs

## [0.1.0] — 2026-05-11

### Public Release

**First public release.** Packaging, sanitization, and distribution improvements for open-source consumption.

- Added `.claude-plugin/` manifest for Claude Code plugin marketplace support
- Restructured directories: commands, hooks, lib, templates, migration at root (no `src/` prefix)

- Added `npx claude-lives` installation support via package.json + bin entry
- Added LICENSE (MIT), CONTRIBUTING.md, .gitignore
- Installer now copies hooks to `~/.claude/claude-lives-lib/hooks/` so they work after npx cleanup
- Installer checks for python3 dependency upfront with clear error message
- Installer registers hooks pointing to installed location (not source tree)
- Removed unimplemented memory backend choice from installer (claude-code is the only backend)
- Uninstaller guards `--delete-data` with `[[ -t 0 ]]` check for non-interactive safety
- Sentinel file is now PPID-scoped to prevent corruption from concurrent sessions
- Lock files are cleaned up after use in inject_memory.sh
- `/sync` uses safer `git add -u` + explicit patterns instead of `git add -A`
- Updated Python requirement from 3.10+ to 3.8+ (no 3.10+ features are used)
- Sanitized all documentation examples to use generic paths

### Session Snapshots (Compaction Fidelity) — 2026-05-11

**Problem:** When Claude Code auto-compacts conversation context during long sessions, earlier work is lossily compressed. Running `/save-session` afterward only captures what survived compaction — early decisions, dead ends, and reasoning are lost.

**Solution:** A PostToolUse hook silently counts tool calls. A CLAUDE.md instruction tells Claude to write incremental snapshots (3-6 bullets, telegraphic) to disk every ~20 tool calls. When `/save-session` runs, it merges disk snapshots with current context for a comprehensive session log.

**New files:**
- `lib/snapshot.sh` — shared library: path resolution, counter ops, init/cleanup, stale detection, config
- `hooks/post_tool_hook.sh` — PostToolUse hook with sentinel-based fast path (<50ms per call)
- `commands/checkpoint.md` — manual `/checkpoint` command for explicit mid-session snapshots
- `tests/test_snapshots.sh` — 36 tests covering library, hook, integration, config, stale detection

**Modified commands:**
- `/save-session` — new Step 2.5 (read snapshots from disk), Step 7.5 (cleanup after merge), Dead Ends section in session log format
- `/resume` — new Step 6: surfaces preserved snapshots from unsaved sessions, offers to merge into memory
- `/checkpoint` — new command: force a snapshot at any point (explicit trigger)

**Hook changes:**
- New PostToolUse hook registered in `~/.claude/settings.json` (fires after every tool call)
- PostToolUse hook uses file-based sentinel (`~/.claude-lives/.snapshot-dir`) for fast path — skips library sourcing and life detection on subsequent calls
- Stop hook: clears sentinel on session end, preserves unsaved snapshots (`has_snapshots: true` in meta), cleans up snapshots if session was already saved

**Security (from code review):**
- `get_snapshot_dir()` validates life/project names with same regex as `detect_life`
- `cleanup_snapshots()` guards `rm -rf` with path boundary check (`$CLAUDE_LIVES_DIR/*`)
- Counter uses `flock` locking (via `increment_counter_locked`) to prevent lost increments from parallel tool calls

**Configuration:**
- `snapshot_tool_threshold: 20` — tool calls between snapshots (configurable per-life)
- `snapshot_max_tokens: 150` — max tokens per snapshot entry
- `snapshot_enabled: true` — master toggle

**Tests:**
- Added test_snapshots.sh with 36 tests
- Updated test_token_optimization.sh: progressive block size limit raised to 2800 chars (snapshot protocol adds ~130 chars)
- Updated test_token_optimization.sh: full-vs-progressive comparison updated (progressive now includes session protocol)
- Updated test_audit_fixes.sh: installer env var check updated for new hook variable names
- Total test count: 329/329 passing (293 previous + 36 snapshots)

### v1.7 Invisible Mode UX + v1.6 Security Hardening — 2026-05-09

**Four parallel audits conducted** (usability, security, benchmark, team scenarios):
- Full report: `docs/audits/full-audit-2026-05-09.md`

**v1.6 Security Hardening:**
- Life name from `.claude-life` now validated with `^[a-zA-Z0-9_-]+$` (was only validated on env var path)
- `flock`-based locking on all CLAUDE.md write operations (prevents concurrent session corruption)
- Append-to-CLAUDE.md path now uses atomic `mktemp`+`mv` (was using `>>` directly)
- `check_injection_patterns()` now **blocks injection** instead of just warning — set `CLAUDE_LIVES_SKIP_SECURITY=1` to override
- Added marker spoofing detection (content containing `CLAUDE-LIVES:END` or `CLAUDE-LIVES:START`)
- Installer/uninstaller: Python subprocess values passed via env vars (was string interpolation — quote-in-path vulnerability)
- Stop hook validates numeric fields before JSON output
- `~/.claude-lives/` created with `chmod 700` permissions
- `.gitignore` added to memory store (excludes `.lock`, `.tmp`, credentials)

**v1.7 Invisible Mode UX:**
- `/save-session` now **auto-compacts** when memory exceeds 80% budget (was: just warns the user)
- `/new-life` reduced from 6 questions to 2 — auto-detects life name (dirname), stack (project files), type hint (child dirs)
- `/resume` stale session message fixed: no longer suggests `/save-session` for recovery (context is gone); instead suggests `git log` / recent file changes
- Session Protocol more aggressive: triggers on closing phrases (goodbye, thanks, done), specifies "before your final response"

**Documentation:**
- README: rewrote Daily Workflow for Minimalist persona, added Known Limitations, added Roadmap table
- New audit report: `docs/audits/full-audit-2026-05-09.md`

**Tests:**
- Added test_audit_fixes.sh with 35 tests
- Updated 4 existing tests for new security behavior (injection blocking)
- Total test count: 293/293 passing (258 previous + 35 audit fixes)

### Search, Timeline & Token Economics — 2026-05-09

**`/search` command (cherry-picked from claude-mem):**
- Full-text search across session logs, memory, handover, and archive files
- Scoped to current life/project by default; `--all` for cross-life search
- `--sessions-only` and `--memory-only` filters
- Uses `rg` (ripgrep) if available, falls back to `grep`
- Case-insensitive by default; results grouped by file with line numbers

**`/timeline` command (cherry-picked from claude-mem):**
- Generates narrative project history from session logs
- Groups by week, synthesizes Key Milestones and Major Decisions sections
- `--weeks N` to limit time range; `--format brief` for one-line-per-session view
- Reads both active session logs and archived sessions

**Token economics in stop hook + `/memory-status`:**
- Stop hook now tracks `session_tokens` (transcript bytes / 4) in `.last-session-meta.json`
- `/memory-status` shows Token Economics section: last session cost, memory store size, efficiency ratio
- Shows "Your memory recovers ~N tokens of context at a cost of ~M tokens per session"

**Tests:**
- Added test_cherry_pick.sh with 33 tests
- Total test count: 258/258 passing (225 previous + 33 cherry-pick)

**Infrastructure:**
- Installer now installs 12 commands (was 10)
- Uninstaller updated for 12 commands

### Structured Question UI for Commands — 2026-05-08

**Commands now use AskUserQuestion tool instead of sequential chat Q&A:**
- `/new-life`: 6 questions batched into 2 structured rounds (core setup + details) with option pickers and multiSelect
- `/import-claude-mem`: project selection, life naming, overwrite confirmation, and bulk mode selection all use structured prompts
- `/borrow`: life selection (when no argument) uses structured picker with available lives as options
- All questions support "Other" for custom text input — options are quick-picks, not limitations

### Auto-Save & Resume — 2026-05-08

**`/fresh` command:**
- New slash command that combines `/save-session` + `/clear` into one workflow
- Runs full save-session workflow, then tells user to run `/clear`
- Eliminates the three-step `/save-session` → `/clear` → `/resume` flow
- `/clear` is a built-in CLI command and cannot be intercepted — `/fresh` saves first, then prompts
- Installer updated: now installs 10 commands (was 9)

**Session Protocol (auto-save):**
- Progressive block now includes a `### Session Protocol` section in CLAUDE.md
- Instructs Claude to proactively run `/save-session` before ending substantial sessions
- Skips trivial Q&A sessions — significance is judged by Claude's own assessment
- Only mechanism that can trigger save, since Stop hooks cannot restart Claude inference

**Enhanced Stop Hook (session metadata):**
- Stop hook now reads transcript JSONL from stdin (`transcript_path`)
- Extracts session metadata: user message count, file modification count
- Writes `.last-session-meta.json` with significance flag (`user_messages > 3` or `files_modified > 0`)
- Passes stdin through to stdout for hook chain compatibility
- Falls back gracefully when no transcript is available

**Stale Session Detection:**
- `/save-session` now writes `.last-saved` timestamp marker (new Step 7)
- `/resume` uses `.last-session-meta.json` + `.last-saved` for precise stale detection
- Significance-aware: only warns about unsaved sessions that had substantial work
- Fallback to legacy `.last-session` vs session log comparison when no meta file exists
- Progressive block includes on-start instruction to check for unsaved sessions

**Tests:**
- Added test_auto_session.sh with 34 tests
- Total test count: 225/225 passing (191 previous + 34 auto-session)

### Three-Layer Model (Global → Life → Project) — 2026-05-08

**Workspace Lives:**
- `.claude-life` marker now has a `type` field: `flat` (default) or `workspace`
- Workspace lives auto-detect projects from child directories (first child = project name)
- Projects are auto-initialized on first use — no `/new-project` command needed
- Each project gets its own memory.md, handover.md, sessions/, and archive/
- Life-level identity and preferences are inherited by all projects

**Detection (`detect_life.sh`):**
- New functions: `detect_life_type()`, `detect_project()`, `get_project_storage_dir()`, `auto_init_project()`
- Flat lives: subdirectories are part of the life (no project splitting)
- Workspace lives: first child directory under life root = project name

**Injection (`inject_memory.sh`):**
- Progressive block for workspace projects: includes life identity + project focus/handover + both context sections
- Header shows `Life: work | Project: project-a` for workspace projects
- File paths section lists both life memory and project memory/handover
- Full mode includes Project Memory and Project Handover sections

**Command Updates:**
- `/new-life` asks whether this is one project or a workspace (6 questions, was 5)
- `/save-session` saves to project storage when in workspace project
- `/resume` reads project handover + life memory + global preferences
- `/compact-memory` compacts project-level memory when in workspace project
- `/memory-status` shows project info and lists sibling projects
- `/cl-inject` documents both flat and workspace injection formats
- `/borrow` supports `life/project` syntax for project-level borrowing

**Stop Hook:**
- Writes `.last-session` to project directory when in workspace project

**Tests:**
- Added test_project_layer.sh with 36 tests
- Total test count: 191/191 passing (155 previous + 36 project layer)

### Token Optimization — 2026-05-07

**Progressive Disclosure:**
- inject_memory.sh now defaults to progressive mode (~500-token compact index)
- CLAUDE.md gets identity, focus, last session context, key facts, and file paths
- Full memory stays in ~/.claude-lives/ files — Claude reads on demand
- `--full` flag available for legacy full-content injection
- Refactored inject_memory.sh: `build_progressive_block()`, `build_full_block()`, `write_block_to_file()`, `extract_section()`, `extract_frontmatter_value()`

**Telegraphic Compression:**
- /save-session now instructs Claude to write all memory in compressed telegraphic style
- /compact-memory includes detailed compression rules with before/after examples
- Target: 40-60% reduction on stored memory content
- Added relevance scoring guidance: recency, actionability, uniqueness
- /new-life updated to write initial memory in telegraphic style

**Security Filtering:**
- `check_injection_patterns()` scans memory files before injection
- Detects: role injection, instruction overrides, delimiter injection
- Warnings logged to stderr if suspicious patterns found

**Command Updates:**
- /resume now reads full memory files (not just CLAUDE.md index) for complete context
- /cl-inject supports `--full` argument for legacy mode, defaults to progressive
- /new-life creates progressive index in CLAUDE.md and notes /import-claude-mem option
- /import-claude-mem supports per-directory mode (auto-detects matching project by directory name)

### Post-Critique Fixes — 2026-05-07
- **C1 (CRITICAL):** inject_memory.sh now uses atomic writes via `mktemp` + `mv` in same directory
- **C2 (CRITICAL):** Mismatched markers (only START or only END) are now detected and repaired
- **C3 (CRITICAL):** `strip_frontmatter()` rewritten — only strips first `---` pair when it starts on line 1; body `---` horizontal rules are preserved
- **C4 (CRITICAL):** claude_mem.py migration backs up existing memory.md/handover.md to `.pre-migration` before overwriting
- **H2 (HIGH):** stop_hook.sh now creates life store directory (sessions/, archive/) when missing
- **H3 (HIGH):** token_count.sh uses `find -type f` to exclude symlinks from directory counts
- **H7 (HIGH):** detect_life.sh validates CLAUDE_LIFE env var with `^[a-zA-Z0-9_-]+$` regex
- **C3 follow-up:** Fixed frontmatter detection to require `---` on line 1 (not mid-file)
- Added 30 targeted critique-fix tests (test_critique_fixes.sh)
- Added `/import-claude-mem` slash command for interactive claude-mem migration
- Installer now copies migration script to ~/.claude/claude-lives-lib/ and installs 9 commands (was 8)
- Total test count: 155/155 passing (95 phase + 30 critique + 30 token optimization)

### Phase 6: Installation, Migration & Sync — 2026-05-07
- Implemented `install.sh` with 4 steps: memory store, slash commands, hooks, library scripts
- Implemented `uninstall.sh` with optional --delete-data flag (preserves data by default)
- Implemented `migration/claude_mem.py` — reads SQLite, groups by project, synthesizes memory
- Implemented `/sync` slash command for git-based cross-machine sync
- Verified: sandboxed install creates structure, registers hooks, preserves existing settings
- Verified: installer is idempotent (no duplicate hooks on second run)
- Verified: uninstaller cleans up commands+hooks but preserves data
- Verified: migration reads actual claude-mem DB (1324 observations → 7 lives)
- Fixed: git commit in installer fails without git config → graceful fallback
- Tests: 19/19 passed

### Phase 5: Observability & Cross-Life — 2026-05-07
- Implemented `/memory-status` slash command with token usage table, session history, and freshness checks
- Implemented `/borrow` slash command with read-only isolation guarantees
- Verified: PHD CLAUDE.md has zero work memory content (and vice versa)
- Verified: global memory appears in both lives
- Verified: borrowing does not modify source life
- Tests: 13/13 passed

### Phase 4: Compression & Memory Decay — 2026-05-07
- Implemented `/compact-memory` slash command with 7-step compression workflow
- Dedup-aware merge: only adds genuinely new facts from session logs
- Memory decay: facts not referenced in last 10 sessions are candidates for archival
- Archive format: monthly files (YYYY-MM.md) with session summaries
- Token budget enforcement: warns at 80% threshold
- Verified: archive is significantly smaller than full session logs
- Fixed: `set -euo pipefail` + `ls *.md` glob failure when dir is empty → switched to `find`
- Tests: 12/12 passed

### Phase 3: Session Management — 2026-05-07
- Implemented `/save-session` slash command with 7-step session save workflow
- Implemented `/resume` slash command with handover surfacing and stale detection
- Implemented `hooks/stop_hook.sh` — writes .last-session timestamp on session end
- Session log schema: frontmatter (date, session, life) + 5 sections (Summary, Decisions, Completed, Pending, Key Findings)
- Handover schema: What Was Happening, Next Steps, Pending Decisions, Key Files
- save-session includes token budget awareness — suggests /compact-memory when over 80%
- Tests: 14/14 passed

### Phase 2: Life Creation & CLAUDE.md — 2026-05-07
- Implemented `/new-life` slash command with 5-question onboarding interview
- Implemented `/cl-inject` helper command for CLAUDE.md memory section updates
- Verified: life creation produces correct structure (marker, memory store, CLAUDE.md injection)
- Verified: existing CLAUDE.md content is preserved during injection
- Verified: two lives (PHD, Tutor) can coexist with isolated memory
- Tests: 14/14 passed

### Phase 1: Foundation — 2026-05-07
- Implemented `lib/detect_life.sh` — walk-up directory detection, env var override, nested life precedence
- Implemented `lib/token_count.sh` — approximate token counting (file, string, directory)
- Implemented `lib/config_defaults.sh` — default budgets, config file override
- Implemented `lib/inject_memory.sh` — CLAUDE.md memory injection with marker-based replacement
- Created 6 template files in `templates/`
- Fixed: inject_memory.sh awk multiline bug → replaced with bash while-read loop
- Tests: 23/23 passed

### Phase 0: Project Setup — 2026-05-07
- Created project directory structure
- Moved original design docs to docs/original/
- Wrote refined design document (docs/design/refined-design.md)
- Wrote 6-phase implementation plan (docs/plan/implementation-plan.md)
- Created project CLAUDE.md
