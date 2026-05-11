# Test Report

**Project:** claude-lives  
**Started:** 2026-05-07

---

## Test Results by Phase

Results are appended as each phase is tested.

---

## Phase 1: Foundation — 2026-05-07

**Result: 23/23 PASSED**

| # | Test | Result |
|---|------|--------|
| 1 | Detect life in current directory | PASS |
| 2 | Walk up directories | PASS |
| 3 | No life found returns exit 1 | PASS |
| 4 | CLAUDE_LIFE env var override | PASS |
| 5 | Detect life with extra YAML fields | PASS |
| 6 | Nested life: inner takes precedence | PASS |
| 7 | Nested life: subdirectory finds inner | PASS |
| 8 | Token count string (~7 for 26 chars) | PASS |
| 9 | Token count file | PASS |
| 10 | Token count non-existent file returns 0 | PASS |
| 11 | Token count directory (only .md files) | PASS |
| 12 | Default life token budget is 4000 | PASS |
| 13 | Default global token budget is 1000 | PASS |
| 14 | Config override from file | PASS |
| 15 | Config fallback to default | PASS |
| 16 | All 6 templates exist | PASS |
| 17 | Templates have correct placeholders | PASS (2 checks) |
| 18 | Inject into new CLAUDE.md (markers, life memory, global memory) | PASS (3 checks) |
| 19 | Inject preserves existing CLAUDE.md content | PASS |
| 20 | Re-inject updates content between markers | PASS |

**Bug fixed during testing:**
- inject_memory.sh: awk `-v` can't handle multiline strings. Replaced with bash while-read loop for marker replacement.
- Test 20 was checking whole file for "feature X" but handover still had it — fixed test to update both memory and handover.

---

## Phase 2: Life Creation & CLAUDE.md Management — 2026-05-07

**Result: 14/14 PASSED**

| # | Test | Result |
|---|------|--------|
| 1 | new-life.md exists with frontmatter | PASS |
| 2 | cl-inject.md exists with frontmatter | PASS |
| 3 | new-life.md has 5+ interview questions | PASS |
| 4 | new-life.md references all required file paths | PASS |
| 5 | Simulated PHD .claude-life created | PASS |
| 6 | PHD memory store has correct structure (sessions/, archive/, memory.md, handover.md, config.yaml) | PASS |
| 7 | PHD CLAUDE.md has CLAUDE-LIVES markers | PASS |
| 8 | PHD CLAUDE.md contains life memory content | PASS |
| 9 | Global memory files created | PASS |
| 10 | Second life (tutor) created alongside first | PASS |
| 11 | PHD and Tutor memories are different (isolation) | PASS |
| 12 | Life detection works for both created lives | PASS |
| 13 | Existing CLAUDE.md content fully preserved after injection | PASS |
| 14 | Re-injection updates memory but preserves project content | PASS |

**Note:** The /new-life slash command itself is a Claude prompt template — it can't be unit-tested. The tests above verify the file structure and injection mechanics that the command relies on. Real-world testing of /new-life happens in Phase 6 end-to-end.

---

## Phase 3: Session Management — 2026-05-07

**Result: 14/14 PASSED**

| # | Test | Result |
|---|------|--------|
| 1 | save-session.md has all required sections (Detect Life, Session Summary, Handover, CLAUDE-LIVES markers) | PASS |
| 2 | save-session.md includes token budget awareness | PASS |
| 3 | resume.md has handover, memory, and stale detection | PASS |
| 4 | save-session.md defines session log schema (Summary, Completed, Pending) | PASS |
| 5 | stop_hook.sh is valid bash syntax | PASS |
| 6 | Stop hook writes .last-session timestamp | PASS |
| 7 | .last-session has valid ISO 8601 timestamp | PASS |
| 8 | Stop hook exits cleanly when no life detected | PASS |
| 9 | Session log files created with correct naming (YYYY-MM-DD-NNN.md) | PASS |
| 10 | Session log has required frontmatter fields | PASS |
| 11 | Session log has all 5 required sections | PASS |
| 12 | Handover has all required sections | PASS |
| 13 | Stale session detected (.last-session newer than latest log) | PASS |
| 14 | CLAUDE.md injection contains memory + handover + global after save | PASS |

**Bug fixed during testing:**
- Stale detection test: original timestamp comparison used `date -j -f` which had parsing issues on macOS. Switched to `stat -f %m` file modification time comparison with a 2s sleep to ensure ordering.

---

## Phase 4: Compression & Memory Decay — 2026-05-07

**Result: 12/12 PASSED**

| # | Test | Result |
|---|------|--------|
| 1 | compact-memory.md has all required sections | PASS |
| 2 | compact-memory.md includes deduplication guidance | PASS |
| 3 | compact-memory.md includes memory decay guidance | PASS |
| 4 | Realistic memory file token count (1066 tokens for ~4KB file) | PASS |
| 5 | Memory under budget (1066 < 4000) | PASS |
| 6 | Below compression threshold (1066 < 3200 = 80%) | PASS |
| 7 | 5 session logs ready for archival | PASS |
| 8 | Archive file created with session summaries | PASS |
| 9 | Archive smaller than full sessions (98 < 375 tokens) | PASS |
| 10 | Sessions moved to archive (5 → 0) | PASS |
| 11 | Decay threshold documented in compact-memory | PASS |
| 12 | decay_session_threshold configurable from config.yaml | PASS |

**Bug fixed during testing:**
- `set -euo pipefail` with `ls *.md` glob exits non-zero when no files match → switched to `find` for counting files.

---

## Phase 5: Observability & Cross-Life — 2026-05-07

**Result: 13/13 PASSED**

| # | Test | Result |
|---|------|--------|
| 1 | memory-status.md has Token Usage, Session History, Freshness | PASS |
| 2 | memory-status.md handles no-life scenario | PASS |
| 3 | borrow.md enforces read-only and temporary access | PASS |
| 4 | borrow.md handles non-existent life | PASS |
| 5 | Life detection isolates phd and work directories | PASS |
| 6 | PHD CLAUDE.md contains ONLY PHD memory (no work leakage) | PASS |
| 7 | Work CLAUDE.md contains ONLY work memory (no PHD leakage) | PASS |
| 8 | Global memory present in both lives | PASS |
| 9 | Can read PHD memory for borrowing from work context | PASS |
| 10 | Borrow does not modify source life's memory (md5 unchanged) | PASS |
| 11 | Available lives can be listed | PASS |
| 12 | Global memory is distinct from life memory | PASS |
| 13 | Global memory has correct structure | PASS |

**No bugs found in this phase.**

---

## Phase 6: Installation, Migration & Sync — 2026-05-07

**Result: 19/19 PASSED**

| # | Test | Result |
|---|------|--------|
| 1 | install.sh valid bash syntax | PASS |
| 2 | install.sh --dry-run shows planned actions | PASS |
| 3 | uninstall.sh valid bash syntax | PASS |
| 4 | Sandboxed install creates memory store | PASS |
| 5 | All 8 slash commands installed | PASS |
| 6 | Stop hook registered in settings.json | PASS |
| 7 | Existing settings preserved | PASS |
| 8 | Git repo initialized | PASS |
| 9 | Idempotent: no duplicate hooks | PASS |
| 10 | Uninstaller removes commands | PASS |
| 11 | Data preserved after uninstall | PASS |
| 12 | Hook removed from settings | PASS |
| 13 | claude_mem.py compiles | PASS |
| 14 | Migration dry run reads DB | PASS |
| 15 | Migration identifies PHD and phd-tutor | PASS |
| 16 | Migration creates 7 life directories | PASS |
| 17 | Migration report generated | PASS |
| 18 | Migrated memory structure correct | PASS |
| 19 | sync.md has git instructions | PASS |

**Bugs fixed during testing:**
- install.sh: `git commit` fails in environments without git user.name/email configured → added graceful fallback with warning message.
- Test sandbox needed git config setup for sandboxed HOME.

---

---

## Post-Critique Fixes — 2026-05-07

**Result: 30/30 PASSED**

Tests added after code-reviewer agent critique identified 4 CRITICAL and 7 HIGH gaps.

| # | Test | Fix Verified | Result |
|---|------|-------------|--------|
| 1 | Atomic write preserves content and adds markers | C1 | PASS |
| 2 | Atomic re-injection updates memory and preserves project content | C1 | PASS |
| 3 | No temporary files left after injection | C1 | PASS |
| 4 | Mismatched START-only fixed to proper marker pair | C2 | PASS |
| 5 | Mismatched marker fix preserves non-marker content | C2 | PASS |
| 6 | Mismatched END-only fixed to proper marker pair | C2 | PASS |
| 7 | Frontmatter stripped: body content preserved | C3 | PASS |
| 8 | Body horizontal rule (---) preserved after frontmatter strip | C3 | PASS |
| 9 | Frontmatter content removed from output | C3 | PASS |
| 10 | Content after body horizontal rule preserved | C3 | PASS |
| 11 | File without frontmatter passes through unchanged | C3 | PASS |
| 12 | Migration creates backup of existing memory.md | C4 | PASS |
| 13 | Migration creates backup of existing handover.md | C4 | PASS |
| 14 | Backup contains original memory content | C4 | PASS |
| 15 | Stop hook creates life directory when missing | H2 | PASS |
| 16 | Stop hook creates sessions/ and archive/ subdirs | H2 | PASS |
| 17 | Stop hook writes .last-session after creating dir | H2 | PASS |
| 18 | Token count directory excludes symlinked files | H3 | PASS |
| 19-23 | Valid life names accepted (phd, my-project, test_life, PHD123, a) | H7 | PASS |
| 24-29 | Invalid life names rejected (../escape, spaces, semicolons, quotes, slashes) | H7 | PASS |
| 30 | Injection creates new CLAUDE.md when none exists | Edge | PASS |

**Bug fixed during testing:**
- `strip_frontmatter()` treated mid-file `---` as frontmatter opener. Fixed to require `---` on line 1.

---

## Token Optimization — 2026-05-07

**Result: 30/30 PASSED**

| # | Test | Category | Result |
|---|------|----------|--------|
| 1 | Progressive injection produces compact output (<2000 chars) | Progressive Disclosure | PASS |
| 2 | Progressive output includes Identity | Progressive Disclosure | PASS |
| 3 | Progressive output includes Focus | Progressive Disclosure | PASS |
| 4 | Progressive output includes last session date | Progressive Disclosure | PASS |
| 5 | Progressive output includes file paths for on-demand reading | Progressive Disclosure | PASS |
| 6 | Progressive output includes Key Context section | Progressive Disclosure | PASS |
| 7 | Progressive output includes next steps | Progressive Disclosure | PASS |
| 8 | Full mode produces larger output than progressive | Progressive Disclosure | PASS |
| 9 | Full mode includes complete memory and handover content | Progressive Disclosure | PASS |
| 10 | Default mode (no flag) uses progressive injection | Progressive Disclosure | PASS |
| 11 | Can switch from progressive to full injection | Progressive Disclosure | PASS |
| 12 | Can switch from full back to progressive injection | Progressive Disclosure | PASS |
| 13 | Clean memory files produce no security warnings | Security Filtering | PASS |
| 14 | Role injection pattern detected | Security Filtering | PASS |
| 15 | Instruction override pattern detected | Security Filtering | PASS |
| 16 | Delimiter injection pattern detected | Security Filtering | PASS |
| 17 | Injection still produces valid output despite warnings | Security Filtering | PASS |
| 18 | save-session.md includes telegraphic compression guidance | Command Guidance | PASS |
| 19 | save-session.md includes compression before/after examples | Command Guidance | PASS |
| 20 | compact-memory.md includes telegraphic compression guidance | Command Guidance | PASS |
| 21 | compact-memory.md includes relevance scoring guidance | Command Guidance | PASS |
| 22 | compact-memory.md includes deduplication rules | Command Guidance | PASS |
| 23 | resume.md explains progressive disclosure context | Command Guidance | PASS |
| 24 | cl-inject.md documents --full flag | Command Guidance | PASS |
| 25 | new-life.md uses progressive injection and telegraphic style | Command Guidance | PASS |
| 26 | extract_section returns correct Identity content | Extract Functions | PASS |
| 27 | extract_section respects max line limit | Extract Functions | PASS |
| 28 | extract_frontmatter_value returns correct value | Extract Functions | PASS |
| 29 | extract_section returns empty for missing section | Extract Functions | PASS |
| 30 | Default injection mode is progressive | Extract Functions | PASS |

**Bugs fixed during testing:**
- `extract_section()` piped `strip_frontmatter` into while-read loop — SIGPIPE on early break with `set -euo pipefail`. Fixed by capturing stripped content into variable first (no pipe).
- Security regex `ignore (all |previous |above )instructions` only matched one qualifier word. "ignore all previous instructions" has two. Fixed to `(all |previous |above )+` (one or more).
- Progressive mode output could exceed full mode for very small test fixtures. Added more realistic memory content to test data.

---

## Three-Layer Model (Project Layer) — 2026-05-08

**Result: 36/36 PASSED**

| # | Test | Category | Result |
|---|------|----------|--------|
| 1 | Workspace type detected from .claude-life | Life Type Detection | PASS |
| 2 | Flat type detected from .claude-life | Life Type Detection | PASS |
| 3 | Missing type field defaults to flat | Life Type Detection | PASS |
| 4 | Project detected in workspace child dir | Project Detection | PASS |
| 5 | Project detected in deep subdir (first child wins) | Project Detection | PASS |
| 6 | No project at workspace root | Project Detection | PASS |
| 7 | No project in flat life subdirectory | Project Detection | PASS |
| 8 | No project at flat life root | Project Detection | PASS |
| 9 | Auto-init creates sessions/ and archive/ dirs | Auto-Initialization | PASS |
| 10 | Auto-init creates project memory.md | Auto-Initialization | PASS |
| 11 | Auto-init creates project handover.md | Auto-Initialization | PASS |
| 12 | Auto-init is idempotent (preserves existing data) | Auto-Initialization | PASS |
| 13 | get_project_storage_dir returns correct path | Auto-Initialization | PASS |
| 14 | Progressive project injection includes life + project header | Project Injection | PASS |
| 15 | Progressive project injection includes life identity | Project Injection | PASS |
| 16 | Progressive project injection includes project focus | Project Injection | PASS |
| 17 | Progressive project injection includes project handover | Project Injection | PASS |
| 18 | Progressive injection has separate Life and Project context sections | Project Injection | PASS |
| 19 | Progressive injection includes project file paths | Project Injection | PASS |
| 20 | Full injection includes Project Memory and Project Handover sections | Project Injection | PASS |
| 21 | Full injection includes Life Memory content | Project Injection | PASS |
| 22 | Flat mode has no Project: in header | Backward Compatibility | PASS |
| 23 | Flat mode uses 'Key Context' label (not 'Life Context') | Backward Compatibility | PASS |
| 24 | Flat mode shows single Handover path | Backward Compatibility | PASS |
| 25 | Flat progressive injection content is correct | Backward Compatibility | PASS |
| 26 | Security filtering scans project memory files | Security | PASS |
| 27 | Stop hook is valid bash syntax | Stop Hook | PASS |
| 28 | new-life.md includes workspace/flat type question | Command Docs | PASS |
| 29 | save-session.md documents workspace project handling | Command Docs | PASS |
| 30 | resume.md documents workspace project handling | Command Docs | PASS |
| 31 | memory-status.md shows project info for workspaces | Command Docs | PASS |
| 32 | cl-inject.md documents project injection format | Command Docs | PASS |
| 33 | .claude-life template includes type placeholder | Command Docs | PASS |
| 34 | borrow.md supports project-level borrowing | Command Docs | PASS |
| 35 | Project name with dots is valid | Edge Cases | PASS |
| 36 | Injection at workspace root (no project) works as flat | Edge Cases | PASS |

---

## Aggregate Results

**Total: 191/191 PASSED (0 failures)**

| Phase | Tests | Passed | Failed |
|-------|-------|--------|--------|
| 1: Foundation | 23 | 23 | 0 |
| 2: Life Creation | 14 | 14 | 0 |
| 3: Session Management | 14 | 14 | 0 |
| 4: Compression & Decay | 12 | 12 | 0 |
| 5: Observability & Cross-Life | 13 | 13 | 0 |
| 6: Installation & Migration | 19 | 19 | 0 |
| Critique Fixes | 30 | 30 | 0 |
| Token Optimization | 30 | 30 | 0 |
| Project Layer | 36 | 36 | 0 |

### Bugs Found & Fixed During Testing

| Phase | Bug | Fix |
|-------|-----|-----|
| 1 | awk `-v` can't handle multiline strings | Replaced with bash while-read loop |
| 3 | macOS `date -j -f` timestamp parsing unreliable | Switched to `stat -f %m` file mod times |
| 4 | `ls *.md` glob fails with `set -euo pipefail` when empty | Switched to `find` |
| 6 | `git commit` fails without git user config in sandbox | Added graceful fallback with warning |
| 6 | macOS `grep -P` (PCRE) not available | Switched to `sed -E` in test runner |
| Critique | inject_memory.sh had no atomic write protection | mktemp + mv in same directory |
| Critique | Mismatched markers silently duplicated content | Detect and repair lone markers |
| Critique | `strip_frontmatter` matched all `---` lines | Only strip first pair starting on line 1 |
| Critique | Migration overwrote existing memory without backup | Backup to `.pre-migration` first |
| Critique | stop_hook silent when life store dir missing | Create dir if absent |
| Critique | token_count included symlinks | Added `-type f` to find |
| Critique | Life names with special chars could break markers | Regex validation `^[a-zA-Z0-9_-]+$` |
| Token Opt | `extract_section` SIGPIPE on early break in pipe | Capture into variable, no pipe |
| Token Opt | Security regex missed multi-word qualifiers | Changed `(word )` to `(word )+` |

### What Was NOT Tested (known limitations)

1. **Slash commands as Claude prompts** — /new-life, /save-session, etc. are prompt templates executed by Claude. They cannot be unit-tested; they require an interactive Claude Code session. Phase 6 sandboxed install verifies the files are installed, but not that Claude follows the instructions correctly.

2. **Concurrent session writes** — file locking with `flock` is mentioned in the design but not implemented in v1.0. Race conditions between two simultaneous sessions in the same life are possible.

3. **Large-scale memory management** — tested with ~1000-token memory files. Behavior at 10,000+ tokens (near budget limits) not tested.

4. **Network failures during /sync** — git push failures are not tested.

5. **Real Claude Code session cycle** — the full loop (install → /new-life → work → /save-session → /clear → /resume) requires an actual Claude Code session. Automated tests simulate the file operations but can't test the Claude interaction.

---

## Auto-Save & Resume — 2026-05-08

**Result: 34/34 PASSED**

| # | Test | Result |
|---|------|--------|
| 1 | Stop hook is valid bash | PASS |
| 2 | Stop hook parses transcript_path from stdin | PASS |
| 3 | Stop hook writes .last-session-meta.json | PASS |
| 4 | Stop hook includes significance filter | PASS |
| 5 | Stop hook passes stdin through to stdout | PASS |
| 6 | Stop hook counts user messages | PASS |
| 7 | Stop hook counts file modifications | PASS |
| 8 | Meta JSON has correct structure and is valid | PASS |
| 9 | Significance: 2 msgs, 0 edits = not significant | PASS |
| 10 | Significance: 5 msgs, 0 edits = significant | PASS |
| 11 | Significance: 1 msg, 1 edit = significant | PASS |
| 12 | Progressive block contains Session Protocol section | PASS |
| 13 | Session Protocol has on-start check instruction | PASS |
| 14 | Session Protocol has before-ending save instruction | PASS |
| 15 | Session Protocol references /save-session command | PASS |
| 16 | Session Protocol references meta file path | PASS |
| 17 | Session Protocol references .last-saved marker | PASS |
| 18 | Full Memory lists session meta file path | PASS |
| 19 | Flat life meta path is correct | PASS |
| 20 | Workspace project meta path is correct | PASS |
| 21 | Workspace project has Session Protocol | PASS |
| 22 | save-session.md documents .last-saved marker | PASS |
| 23 | save-session.md has 'Mark Session as Saved' step | PASS |
| 24 | save-session.md covers both flat and workspace .last-saved paths | PASS |
| 25 | resume.md references .last-session-meta.json | PASS |
| 26 | resume.md references .last-saved for stale comparison | PASS |
| 27 | resume.md has significance-aware stale detection | PASS |
| 28 | resume.md has fallback detection for missing meta file | PASS |
| 29 | Stale detection: significant session without .last-saved = unsaved | PASS |
| 30 | Stale detection: .last-saved present = session was saved | PASS |
| 31 | Stale detection: non-significant session = no warning needed | PASS |
| 32 | Stop hook checks transcript file exists before parsing | PASS |
| 33 | Stop hook checks for terminal stdin before reading | PASS |
| 34 | Transcript parsing: correctly counts 5 user msgs, 2 file edits | PASS |

**Coverage:**
- Stop hook metadata extraction (7 tests)
- Significance threshold logic (3 tests)
- Session Protocol in progressive block (10 tests)
- Save-session .last-saved marker (3 tests)
- Resume stale detection (4 tests)
- Integration/simulation (6 tests)
- Transcript JSONL parsing (1 test)

---

## Aggregate — 2026-05-08

| Suite | Tests | Result |
|-------|-------|--------|
| Phase 1: Foundation | 23 | 23/23 |
| Phase 2: Life Creation | 14 | 14/14 |
| Phase 3: Session Management | 14 | 14/14 |
| Phase 4: Compression & Decay | 12 | 12/12 |
| Phase 5: Observability | 13 | 13/13 |
| Phase 6: Installation | 19 | 19/19 |
| Critique Fixes | 30 | 30/30 |
| Token Optimization | 30 | 30/30 |
| Project Layer | 36 | 36/36 |
| Auto-Save & Resume | 34 | 34/34 |
| **Total** | **225** | **225/225** |

---
