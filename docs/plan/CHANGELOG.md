# Plan Changelog

## 2026-05-09 — v1.7 Invisible Mode UX + v1.6 Security Hardening

- Four parallel audits: usability (5 personas), security, competitive benchmark, team scenarios
- v1.6 Security: life name validation on file path, flock locking, injection blocking, installer env vars, numeric validation, chmod 700, .gitignore
- v1.7 UX: auto-compact in save-session, 2-question /new-life, fixed stale session message, aggressive Session Protocol
- Benchmark: unique differentiator is life isolation; gap is semantic search + auto-capture reliability vs claude-mem
- Team analysis: proposed gitignored injection target, READONLY mode, team-memory.md layer (deferred to future release)
- 35 new tests (test_audit_fixes.sh), 4 existing tests updated. Total: 293/293 passing
- Full audit report: docs/audits/full-audit-2026-05-09.md

## 2026-05-09 — v1.5 Search, Timeline & Token Economics

- `/search` command: full-text search across sessions, memory, handover, and archive
- `/timeline` command: narrative project history synthesized from session logs
- Token economics: `session_tokens` tracked in stop hook meta, shown in `/memory-status`
- Cherry-picked from claude-mem benchmark: search and timeline were the biggest feature gaps
- Skipped: semantic search (too heavy), daemon (against design), multi-language (not needed)
- 33 new tests added (test_cherry_pick.sh), total: 258/258 passing

## 2026-05-08 — v1.4 Auto-Save & Resume

- Session Protocol added to progressive block — Claude auto-saves before ending substantial sessions
- Enhanced stop hook: reads transcript JSONL, extracts metadata, writes `.last-session-meta.json`
- Significance filter: `user_messages > 3` OR `files_modified > 0` = substantial session
- `/save-session` writes `.last-saved` marker for precise stale detection
- `/resume` uses metadata + saved marker for significance-aware unsaved session warnings
- Stop hook cannot restart Claude inference — CLAUDE.md instruction is the only viable auto-save mechanism
- 34 new tests added (test_auto_session.sh), total: 225/225 passing

## 2026-05-08 — v1.3 Three-Layer Model

- Added three-layer hierarchy: Global → Life → Project
- Two life types: `flat` (default, life = project) and `workspace` (children are projects)
- Project auto-detection: first child directory under workspace life root = project name
- Project auto-initialization: storage created automatically on first use
- All slash commands updated for project awareness
- Backward compatible: flat lives work exactly as before, no type field defaults to flat
- 36 new tests added (test_project_layer.sh), total: 191/191 passing

## 2026-05-07 — v1.2 Token Optimization

- Added token optimization phase based on research of 25+ GitHub repos (Caveman 55K stars, RTK 43K, Context Mode 14K, etc.)
- Progressive disclosure: CLAUDE.md injection reduced from ~6500 to ~500 tokens (compact index with file paths)
- Telegraphic compression: all memory writes use compressed style (40-60% reduction)
- Security filtering: prompt injection detection before CLAUDE.md injection
- Relevance scoring with decay guidance in /compact-memory
- All slash commands updated for progressive disclosure awareness
- Architectural change: inject_memory.sh refactored into progressive/full modes with shared write logic

## 2026-05-07 — v1.1 Post-Critique Hardening

- Added critique fix phase after Phase 6 (code-reviewer agent identified 4 CRITICAL + 7 HIGH gaps)
- Added test_critique_fixes.sh with 30 targeted tests for all fixes
- Strengthened frontmatter stripping to require `---` on line 1 (not mid-file)
- No architectural changes — all fixes are behavioral hardening of existing components
- Test count increased from 95 to 125

## 2026-05-07 — v1.0 Initial Plan

- Created 6-phase implementation plan from refined design
- Key architectural decisions from critical analysis:
  - `.claude-life` marker file instead of CLAUDE.md frontmatter
  - CLAUDE.md injection instead of SessionStart hook (more reliable)
  - Slash commands as intelligence (Claude does heavy lifting)
  - Approximate token counting (4 chars ≈ 1 token)
  - Deferred self-improving skills to v2.0
  - Deferred global auto-promotion to v2.0
- Testing strategy: unit tests + real scenario tests per phase
- Real test directories: used local project directories for scenario validation
