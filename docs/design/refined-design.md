# claude-lives: Refined Design Document

**Version:** 1.0  
**Date:** 2026-05-07  
**Status:** Approved for implementation

---

## 1. Problem

Claude Code is stateless. Every `/clear` or new session starts with zero memory. For users who operate across multiple professional contexts (e.g., work, PhD research, design practice), this means:

- No context isolation: work knowledge bleeds into research sessions
- No continuity: "what were we working on?" requires manual re-explanation
- No self-maintenance: memory grows without pruning or compression

Existing tools (claude-mem, Obsidian setups) use flat, append-only memory with no namespace isolation, no relevance decay, and no deduplication. By 30+ sessions, context injection consumes 30-40% of the window before real work begins.

## 2. Solution: claude-lives

A Claude Code plugin that introduces **lives** — fully isolated memory contexts tied to directory trees. The core insight: Claude Code already reads CLAUDE.md from the working directory. claude-lives formalizes this into a structured, self-maintaining memory system.

### 2.1 Design Principles

1. **Build on Claude Code's native systems** — use CLAUDE.md for injection, don't create parallel systems
2. **Directory-driven detection** — `cd ~/phd` = PhD mode, zero friction
3. **Slash commands as intelligence** — Claude does the heavy lifting (summarization, compression), not external scripts
4. **Minimal external code** — bash for hooks/install, Python only where unavoidable (migration)
5. **Memory decays** — old facts lose relevance over time, not just storage space

### 2.2 What This Is Not

- Not an Obsidian replacement
- Not a codebase analysis tool (Graphify is separate)
- Not a paid service or cloud dependency
- Not a running server or MCP

## 3. Architecture

### 3.1 Three Memory Layers

| Layer | Scope | Location | Token Budget |
|-------|-------|----------|-------------|
| **Global** | All lives | `~/.claude-lives/global/memory.md` | 1,000 |
| **Life** | One life, all projects in it | `~/.claude-lives/{life}/memory.md` | 4,000 |
| **Handover** | Last session state | `~/.claude-lives/{life}/handover.md` | 1,500 |

**Total budget: ~6,500 tokens** (configurable per life). This is injected into CLAUDE.md which Claude Code reads automatically on every session start and after `/clear`.

### 3.2 File Structure

```
~/.claude-lives/                    # Central memory store
  config.yaml                       # Global config
  global/
    memory.md                       # Cross-life preferences
  {life-name}/                      # Per-life directory
    memory.md                       # Compressed life memory
    handover.md                     # What was happening, what's next
    config.yaml                     # Per-life config (token budgets, etc.)
    sessions/                       # Session logs
      2026-05-07-001.md
      2026-05-07-002.md
    archive/                        # Compressed old sessions
      2026-04.md

{life-root-directory}/
  .claude-life                      # Life marker file (YAML)
  CLAUDE.md                         # Contains auto-managed memory section
```

### 3.3 Life Marker File (.claude-life)

```yaml
name: phd
created: 2026-05-07
description: PhD research in AI/ML
token_budget:
  life: 4000
  handover: 1500
```

Separate from CLAUDE.md to avoid conflating life identity with project instructions. Projects can have their own CLAUDE.md without interfering with life detection.

### 3.4 CLAUDE.md Memory Injection

The CLAUDE.md in a life's root directory contains an auto-managed section:

```markdown
# Existing project instructions here...

<!-- CLAUDE-LIVES:START:phd -->
## Life: PHD Research

### Global Preferences
[Auto-injected from ~/.claude-lives/global/memory.md]

### Life Memory
[Auto-injected from ~/.claude-lives/phd/memory.md]

### Handover
[Auto-injected from ~/.claude-lives/phd/handover.md]
<!-- CLAUDE-LIVES:END -->
```

This section is auto-updated by `/save-session`. Everything between the markers is managed by claude-lives. Content outside the markers is untouched.

**Why CLAUDE.md?** It's the only mechanism that:
- Loads automatically on every session start
- Survives `/clear`
- Requires zero user action to inject context

### 3.5 Life Detection Algorithm

```
1. Start at current working directory
2. Check for .claude-life file
3. If not found, walk up one directory
4. Repeat until found or hit filesystem root
5. If found: load that life's memory
6. If not found: load global memory only (no life context)
```

**Override:** `CLAUDE_LIFE=phd` environment variable forces a life regardless of directory.

## 4. Slash Commands

| Command | Description |
|---------|-------------|
| `/new-life` | Onboarding interview, creates life structure |
| `/save-session` | Save current session to life memory |
| `/resume` | Surface handover and continue where you left off |
| `/memory-status` | Show memory state, token usage, last save |
| `/borrow <life>` | Temporarily inject another life's memory |
| `/compact-memory` | Force memory compression |
| `/checkpoint` | Mid-session snapshot to preserve context before compaction |
| `/sync` | Git commit and push memory store |

### 4.1 How Slash Commands Work

Slash commands are markdown prompt templates. Claude reads them and uses its native tools (Read, Write, Bash) to execute. The intelligence is in Claude, not in external scripts.

### 4.2 /save-session Flow

1. Detect current life (read .claude-life)
2. Read existing memory.md
3. Summarize what happened this session (decisions, completions, pending work)
4. Write session log to `sessions/{date}-{seq}.md`
5. Update handover.md with pending items and next steps
6. Merge new facts into memory.md (dedup-aware: only add genuinely new info)
7. Re-inject memory into CLAUDE.md between the markers
8. Report what was saved

### 4.3 /new-life Onboarding

Asks structured questions:
1. What is this life for?
2. What kinds of tasks do you usually do here?
3. Specific tools, languages, or workflows?
4. Current status — fresh start or mid-way?
5. Things Claude should never do in this context?

Then creates all files and CLAUDE.md section from the answers.

## 5. Session Management

### 5.1 Saving Sessions

Primary: `/save-session` command (explicit, reliable)
Secondary: CLAUDE.md instructions remind Claude to suggest saving before ending

The Stop hook writes a lightweight timestamp to `~/.claude-lives/{life}/.last-session` so the next session can detect if the previous session was saved or not.

### 5.2 Mid-Session Snapshots (Compaction Fidelity)

During long sessions, Claude Code auto-compacts conversation context when the context window fills up. This lossily compresses earlier work — early decisions, dead ends, and reasoning are lost. When `/save-session` runs afterward, it can only see what survived compaction.

**Solution:** A two-component system:

1. **PostToolUse hook** (`hooks/post_tool_hook.sh`) — fires after every tool call, increments a counter in `~/.claude-lives/{life}/.session-snapshots/counter`. Uses a file-based sentinel (`~/.claude-lives/.snapshot-dir`) for fast-path caching: subsequent calls skip library sourcing and life detection entirely (~40ms per call).

2. **CLAUDE.md Session Protocol instruction** — tells Claude to check the counter when it reads/writes files. When the counter exceeds 20, Claude writes a brief incremental snapshot (3-6 bullets, telegraphic) to `.session-snapshots/snapshots.md` and resets the counter. This instruction survives compaction because CLAUDE.md is always reloaded.

**Merge flow:** `/save-session` Step 2.5 reads `snapshots.md` from disk and uses it as additional context when writing the session log. The session log synthesizes both snapshots (early/mid work) and current in-memory context (recent work). Step 7.5 cleans up the snapshot directory after merge.

**Safety net:** If the session ends without saving, the Stop hook preserves snapshots on disk and writes `"has_snapshots": true` to `.last-session-meta.json`. `/resume` detects this and offers to merge preserved snapshots into memory.

**Manual trigger:** `/checkpoint` allows explicit snapshot creation at any point.

### 5.3 Stale Session Detection

On session start, if `.last-session` timestamp is newer than the latest session log, the previous session was NOT saved. The CLAUDE.md instructions tell Claude to:
1. Note that the previous session may not have been saved
2. Offer to reconstruct from git activity or file changes
3. Continue normally regardless

### 5.4 Handover Notes

handover.md captures:
- What was literally being worked on
- What the next step was going to be
- Any blocking issues or decisions pending
- Key files that were being edited

This is surfaced by `/resume` and also visible in the CLAUDE.md injection.

## 6. Memory Compression

### 6.1 When Compression Runs

- Manual: `/compact-memory` command
- Auto-suggested: when `/save-session` detects memory exceeds 80% of token budget
- Claude suggests compression; user confirms

### 6.2 Compression Algorithm

1. Read current memory.md
2. Read all session logs since last compression
3. Claude produces a merged memory: "Given this existing memory and these session logs, produce a compressed memory that contains all important facts. Do not repeat information already in memory. Remove facts that are no longer relevant."
4. Write new memory.md
5. Move compressed session logs to `archive/`
6. Record compression timestamp in memory.md frontmatter

### 6.3 Memory Decay

Each fact in memory.md carries an implicit relevance. During compression:
- Facts reinforced by recent sessions are kept
- Facts not referenced in the last 10 sessions are candidates for archival
- Archived facts move to `archive/` — not deleted, but not injected
- `/recall <topic>` can pull archived facts back if needed

### 6.4 Token Counting

Approximate: 1 token ≈ 4 characters. This is a heuristic good enough for budget management. Exact tokenizer alignment with Claude's actual tokenizer is unnecessary — we're managing a soft budget, not a hard limit.

## 7. Cross-Life Access

### 7.1 /borrow

`/borrow phd` in a work session:
1. Reads `~/.claude-lives/phd/memory.md`
2. Presents the memory as temporary context
3. Does NOT modify the work life's memory
4. Memory returns to work-only on next `/clear` or session start

### 7.2 Global Memory

`~/.claude-lives/global/memory.md` contains cross-life preferences:
- Communication style
- Tool preferences
- Formatting preferences

Updated manually or via `/save-session` when a preference is explicitly stated as universal.

## 8. Installation

```bash
curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash
# or
git clone ... && cd claude-lives && ./install.sh
```

The install script:
1. Creates `~/.claude-lives/` with structure
2. Copies slash commands to `~/.claude/commands/`
3. Registers the Stop hook in `~/.claude/settings.json` (non-destructive merge)
4. Creates `~/.claude-lives/global/memory.md` with initial content
5. Runs a brief global onboarding: "Describe yourself as a Claude Code user"

Requirements: bash, git, Claude Code. Python 3.10+ only for claude-mem migration.

## 9. claude-mem Migration

For users migrating from claude-mem:
1. Read claude-mem memory files
2. Present each memory entry to Claude for classification (which life? or global?)
3. Write sorted memories to appropriate life directories
4. Flag ambiguous entries for manual review
5. Generate migration report

This is a one-time operation. Deferred to Phase 6 of implementation.

## 10. Git Sync

`/sync` commits and pushes `~/.claude-lives/` to a git remote:
```bash
cd ~/.claude-lives && git add -A && git commit -m "sync: {date}" && git push
```

On a new machine: `git clone <url> ~/.claude-lives && ./install.sh --hooks-only`

## 11. Reliability

### 11.1 Concurrent Sessions

File locking via `flock` on write operations to memory.md and handover.md. If lock fails, write to a `.pending` file that merges on next save.

### 11.2 Observability

`/memory-status` shows:
- Current life name and path
- Token usage per layer (current / budget)
- Last save timestamp
- Number of unsaved sessions
- Compression history

## 12. Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| `.claude-life` marker, not CLAUDE.md frontmatter | Separation of concerns: life identity vs project instructions |
| Slash commands, not Python scripts | Claude's intelligence > scripted logic. Simpler to maintain. |
| CLAUDE.md injection, not SessionStart hook | CLAUDE.md is guaranteed to load. Hook availability varies. |
| Approximate token counting | Soft budget. Exact tokenizer not needed. |
| No MCP server | Simplicity. Hooks + commands + files are sufficient. |
| No auto-compression | User confirms. Prevents accidental data loss. |
| PostToolUse counter + CLAUDE.md snapshots | No compaction hook exists. Proactive capture via tool-call counting + model-driven summarization preserves session fidelity. |
| Git sync, not cloud service | User controls their data. Works offline. |

## 13. Out of Scope (v1.0)

- Self-improving skill detection (v2.0)
- Auto-promotion of patterns to global memory (v2.0)
- Vector search / embeddings over memory
- Multi-user / team memory sharing
- GUI or web dashboard
- Windows support
