# Implementation Plan

**Version:** 1.0  
**Date:** 2026-05-07

---

## Overview

6 phases, each with implementation + testing. Later phases build on earlier ones but each phase produces a testable artifact.

## Phase 1: Foundation (Core Detection & Memory Structure)

### Goal
Life detection works. Memory store directory structure is correct. Config is readable.

### Implementation
1. `lib/detect_life.sh` — walk-up algorithm to find `.claude-life`
2. `lib/token_count.sh` — approximate token counter (chars/4)
3. `templates/` — templates for `.claude-life`, `config.yaml`, `memory.md`
4. Config schema definition in `lib/config_defaults.sh`

### Testing
| Test | Method | Pass Criteria |
|------|--------|---------------|
| Detect life in current dir | Create `.claude-life` in /tmp/test-life/, run detect_life.sh from there | Returns "test" |
| Walk up directories | Create `.claude-life` in /tmp/test-life/, run from /tmp/test-life/sub/deep/ | Returns "test" |
| No life found | Run from /tmp/ (no .claude-life anywhere useful) | Returns empty, exit 1 |
| Env var override | Set CLAUDE_LIFE=override, run from anywhere | Returns "override" |
| Token counter accuracy | Count known strings | Within 20% of actual Claude token count |
| Real path test | Create .claude-life in a real project directory | Detects life name from directory basename |

### Deliverables
- [ ] detect_life.sh working and tested
- [ ] token_count.sh working and tested
- [ ] Template files created
- [ ] Config schema defined

---

## Phase 2: Life Creation & CLAUDE.md Management

### Goal
`/new-life` creates a fully initialized life. CLAUDE.md injection works.

### Implementation
1. `commands/new-life.md` — onboarding slash command
2. `commands/cl-inject.md` — helper to inject/update CLAUDE.md memory section
3. `lib/inject_memory.sh` — script to inject memory between markers in CLAUDE.md

### Testing
| Test | Method | Pass Criteria |
|------|--------|---------------|
| Create new life | Run `/new-life` in a test directory | .claude-life created, ~/.claude-lives/{name}/ created with all files |
| CLAUDE.md created | After /new-life, check CLAUDE.md exists | Has CLAUDE-LIVES markers with onboarding memory |
| CLAUDE.md preserves existing content | Create CLAUDE.md with content first, then /new-life | Existing content preserved, markers added |
| Memory store structure | Check ~/.claude-lives/{name}/ | Has memory.md, handover.md, config.yaml, sessions/ |
| Real scenario: my-research | Run /new-life in my-research directory with real answers | my-research life fully initialized |
| Real scenario: my-tutor | Run /new-life in phd-tutor directory | my-tutor life fully initialized |

### Deliverables
- [ ] /new-life slash command working
- [ ] CLAUDE.md injection working
- [ ] inject_memory.sh working
- [ ] Two real lives created (my-research, my-tutor)

---

## Phase 3: Session Management (Save & Resume)

### Goal
`/save-session` captures session state. `/resume` picks up where left off. Memory persists across `/clear`.

### Implementation
1. `commands/save-session.md` — save current session to life memory
2. `commands/resume.md` — load handover and continue
3. `hooks/stop_hook.sh` — writes .last-session timestamp on session end
4. Hook registration logic in install.sh (partial)

### Testing
| Test | Method | Pass Criteria |
|------|--------|---------------|
| Save session | Start session in my-research life, do some work, run /save-session | Session log written, handover updated, CLAUDE.md updated |
| Session log format | Read session log file after save | Has date, summary, decisions, pending items |
| Handover format | Read handover.md after save | Has "what was happening" and "next steps" |
| CLAUDE.md updated | Read CLAUDE.md after save | Memory section between markers is updated |
| Survives /clear | Save session, run /clear, check if Claude has context | Claude knows life context and recent work |
| Resume after save | Save, start new session, run /resume | Handover surfaced, Claude knows where we left off |
| Stale session detection | Save, then start new session without saving | Claude notes previous session may not have been saved |
| Multiple saves | Save twice in one session | Both logs written, memory merged correctly |
| Real scenario | Full my-research workflow: discuss research, /save-session, /clear, ask "what are we working on?" | Claude accurately recalls my-research context |

### Deliverables
- [ ] /save-session working end-to-end
- [ ] /resume working
- [ ] Stop hook registered and firing
- [ ] Survives /clear test passing
- [ ] Real my-research scenario tested

---

## Phase 4: Compression & Memory Decay

### Goal
Memory stays within token budget. Old facts are archived, not permanently stored.

### Implementation
1. `commands/compact-memory.md` — manual compression trigger
2. Compression instructions embedded in /save-session (suggest when exceeding 80%)
3. Archive management in session save logic

### Testing
| Test | Method | Pass Criteria |
|------|--------|---------------|
| Compression reduces size | Build up large memory (10+ sessions), run /compact-memory | memory.md smaller, no important info lost |
| Dedup works | Add same facts multiple times, compress | Facts appear once, not repeated |
| Archive created | After compression, check archive/ | Old session logs moved to archive |
| Token budget respected | After compression, count tokens | Under configured budget |
| Decay works | Add facts, don't reference for many sessions, compress | Old unreferenced facts archived |
| Empty memory compression | Run compact on fresh life | No errors, memory unchanged |
| Real scenario | my-research life with 5+ saved sessions, compress | Memory is concise and accurate |

### Deliverables
- [ ] /compact-memory working
- [ ] Auto-suggestion when memory is large
- [ ] Archive directory populated after compression
- [ ] Token counting accurate within bounds

---

## Phase 5: Observability & Cross-Life

### Goal
Users can inspect memory state. Cross-life borrowing works with isolation.

### Implementation
1. `commands/memory-status.md` — show memory state
2. `commands/borrow.md` — temporarily inject another life's memory
3. `~/.claude-lives/global/memory.md` — global memory layer

### Testing
| Test | Method | Pass Criteria |
|------|--------|---------------|
| Memory status shows info | Run /memory-status in my-research life | Shows life name, token usage, last save, session count |
| Token usage accurate | Compare /memory-status numbers with actual file sizes | Within 20% |
| Borrow injects memory | In my-research life, run /borrow tutor | my-tutor memory shown, can answer tutor questions |
| Borrow doesn't persist | After /borrow, run /clear | Only my-research memory remains |
| Borrow non-existent | /borrow nonexistent | Clear error message |
| Global memory works | Add global preference, verify it appears in all lives | Preference injected in my-research and my-tutor sessions |
| Real scenario | In my-research session, borrow tutor context to check student work | Cross-reference works, isolation returns after |

### Deliverables
- [ ] /memory-status working
- [ ] /borrow working with isolation guarantee
- [ ] Global memory layer functional

---

## Phase 6: Installation, Migration & Sync

### Goal
One-command install. claude-mem users can migrate. Git sync works.

### Implementation
1. `install.sh` — full installer
2. `uninstall.sh` — clean removal
3. `migration/claude_mem.py` — migration script
4. `commands/sync.md` — git sync command

### Testing
| Test | Method | Pass Criteria |
|------|--------|---------------|
| Fresh install | Run install.sh on clean system (simulated) | All structure created, hooks registered, commands copied |
| Idempotent install | Run install.sh twice | No duplicates, no errors |
| Hook registration | Check settings.json after install | Stop hook present, existing hooks preserved |
| Uninstall | Run uninstall.sh | Hooks removed, commands removed, data preserved (with flag to delete) |
| claude-mem migration | Run migration against actual claude-mem data | Memories sorted into lives, report generated |
| Migration report | Check migration report | Shows all assignments, flags ambiguous |
| Sync push | Run /sync with git remote | Commits and pushes successfully |
| Sync pull | Clone on simulated new machine | Memory restored |
| Real scenario | Migrate actual claude-mem → claude-lives, verify my-research memories landed in my-research life | Correct classification |

### Deliverables
- [ ] install.sh working (tested with --dry-run)
- [ ] uninstall.sh working
- [ ] claude-mem migration functional
- [ ] /sync working
- [ ] Full end-to-end from install to daily use

---

## Execution Order

```
Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6
  ↓          ↓          ↓          ↓          ↓          ↓
 Test       Test       Test       Test       Test       Test
  ↓          ↓          ↓          ↓          ↓          ↓
 Log        Log        Log        Log        Log        Log
```

Each phase:
1. Implement
2. Run tests (unit + real scenario)
3. Log results to test-report.md
4. Log changes to CHANGELOG.md
5. If implementation changes affect the plan, update plan + plan CHANGELOG

## Success Criteria

The system is ready when:
1. All 6 phases pass their tests
2. A real `/clear` → "what are we working on?" returns life-specific context
3. my-research and my-tutor lives are fully isolated
4. Memory is under token budget after 5+ sessions
5. Install works from scratch in one command
6. claude-mem data is migrated successfully
