# claude-lives Full Audit — 2026-05-09

Four parallel audits: usability (5 personas), security, competitive benchmark, team scenario.

---

## 1. Usability Audit

### Persona Analysis

| Persona | Daily Commands | Pain Points |
|---------|---------------|-------------|
| **Minimalist** (actual user) | `/fresh` only | /fresh needs 2 steps (+/clear), auto-save unreliable, no auto-compact |
| **Power User** (5+ lives) | `/fresh`, `/search`, `/timeline` | No /list-lives dashboard, no /delete-life, /sync conflict handling unclear |
| **Newcomer** (first plugin) | None consistently | 6 setup questions overwhelming, flat-vs-workspace confusing, forgets to save |
| **Team Lead** | `/sync`, `/memory-status` | No shared team memory, no enforcement, fundamentally single-user |
| **Researcher** (multi-month) | `/resume`, `/save-session`, `/timeline` | Progressive index too thin after weeks away, no session tagging, 4K budget tight |

### Command Usage Reality

| Command | How often anyone uses it |
|---------|--------------------------|
| `/fresh` | Daily (the only daily command) |
| `/save-session` | Weekly at best (most rely on auto-save) |
| `/resume` | Weekly (when progressive index isn't enough) |
| `/search` | Monthly |
| `/timeline` | Monthly |
| `/memory-status` | Monthly |
| `/compact-memory` | Rarely (nobody does this voluntarily) |
| `/borrow` | Almost never |
| `/sync` | Almost never |
| `/new-life` | Once per project |
| `/import-claude-mem` | Once ever |
| `/cl-inject` | Never (internal) |

### Critical UX Problems

**CRITICAL: Auto-save is a suggestion, not a guarantee.** The Session Protocol in CLAUDE.md asks Claude to save before ending. But Claude "ending" is not deterministic. If the user closes the terminal, Claude can't run commands. The stop hook fires but only writes metadata, not actual memory. For the Minimalist who relies on `/fresh`, forgetting it once = lost context.

**CRITICAL: No auto-compact.** Memory grows silently. `/save-session` warns at 80% budget but for a Minimalist who just uses `/fresh`, they'd have to notice the warning AND know about `/compact-memory`. There's no automatic trigger. After ~15-20 sessions, quality degrades.

**HIGH: /fresh requires two commands.** `/fresh` saves then says "Now run /clear." Every day, twice. The tool can't intercept `/clear` (real constraint), but this is the #1 daily friction point.

**HIGH: Stale session recovery is misleading.** When `/resume` detects an unsaved session, it says "Run /save-session to recover context." But the context is gone from the conversation. `/save-session` in a fresh session saves nothing useful.

**MEDIUM: /new-life asks 6 questions.** Auto-detect: name from dirname, type defaults to flat, stack from existing files. Ask one question: "What's this project about?" Drop setup from 2 min to 10 sec.

### "Invisible Mode" Assessment

The user wants: vanilla Claude Code + /fresh + everything else background.

**What works:** CLAUDE.md progressive index loads automatically. Stop hook runs silently. Life detection is automatic. Core design is sound.

**What breaks:** No auto-compact (memory bloats), auto-save is unreliable (terminal close = lost), progressive index too thin for long gaps, session logs accumulate with no auto-archiving.

**Verdict:** Invisible mode works for ~2 weeks before requiring manual intervention that the Minimalist won't do.

---

## 2. Security Audit

### Findings Summary

| Severity | Count | Key Issues |
|----------|-------|------------|
| CRITICAL | 2 | Life name validation missing on file-read path; no CLAUDE.md write locking |
| HIGH | 4 | Path traversal via life names; unvalidated JSON metadata; Python string injection in installer; injection warnings don't block |
| MEDIUM | 5 | Config value type validation; ~/.claude-lives/ permissions; frontmatter regex edge case; migration path traversal; silent error swallowing in stop hook |
| LOW | 3 | Narrow injection pattern set; git add -A in /sync; non-interactive read -p in uninstaller |

### Critical Details

**C1 — Life name from `.claude-life` not validated.** The `CLAUDE_LIFE` env var is validated with `^[a-zA-Z0-9_-]+$` regex, but the `name:` field read from `.claude-life` file has NO validation. A malicious `.claude-life` with `name: ../../.ssh/authorized_keys` would cause path traversal. Fix: apply same regex to file-read path in `detect_life()`.

**C2 — No file locking on CLAUDE.md.** The update-existing-markers path uses mktemp+mv (safe). But the append-new-markers path uses `>>` directly. Two concurrent sessions = duplicate markers = corruption. No `flock` anywhere. Fix: flock around all write operations.

**H1 — Path traversal via life names.** Even without C1, life names flow into `"$CLAUDE_LIVES_DIR/$life_name/memory.md"` without normalization. Fix: validate + realpath check.

**H4 — Injection detection warns but doesn't block.** `check_injection_patterns()` finds prompt injection in memory files, logs to stderr, then proceeds to inject the malicious content into CLAUDE.md anyway. Fix: abort injection on detection, require explicit override.

### Overall Posture

**MEDIUM risk for personal use. HIGH risk if memory files come from untrusted sources (shared repos, workspace lives in public codebases).** The design is fundamentally sound (atomic writes in most paths, pipefail, regex on env var path). Gaps are edge cases in the file-read path that didn't get the same rigor.

---

## 3. Competitive Benchmark

### Market Position

| | claude-lives | claude-mem (46K stars) | Claude Code native |
|--|-------------|----------------------|-------------------|
| **Context isolation** | Core differentiator (Global->Life->Project) | Single pool, no isolation | Per-repo dirs, no isolation |
| **Token efficiency** | ~500 tokens/session (10x better) | ~7,500-12,000 tokens/session | Unknown (internal) |
| **Infrastructure** | Zero (bash + markdown) | SQLite + Chroma + Bun daemon + MCP server | Zero (built-in) |
| **Search** | Full-text (rg/grep) | Semantic (Chroma vectors) + FTS5 | None |
| **Auto-capture** | Soft (Session Protocol instruction) | Hard (observer AI watches every tool use) | Auto Memory (writes as it works) |
| **Multi-tool** | Claude Code only | Claude Code, Cursor, Gemini CLI, Windsurf, Codex CLI | Claude Code only |
| **Setup** | git clone + ./install.sh | Plugin install, needs Bun | Zero |
| **Storage** | Human-readable markdown | Opaque SQLite + Chroma | Internal markdown |
| **Team support** | None | None | CLAUDE.md in git |
| **Maturity** | New, 258 tests | 46K stars, 1840 commits, 109 contributors | Official, stable |

### Unique Strengths

1. **Life isolation is unmatched.** No other tool separates `cd ~/phd` from `cd ~/work/project-a` automatically.
2. **Zero infrastructure.** No daemons, no databases, no ports. Pure files.
3. **Transparent storage.** Everything is grep-able, git-able markdown.
4. **Token-conscious from the ground up.** 10x fewer tokens than claude-mem per session.

### Biggest Gaps

1. **Semantic search.** claude-mem's Chroma vector search is categorically better for large memory stores.
2. **Auto-capture reliability.** claude-mem's observer AI captures every tool use automatically. claude-lives relies on Claude following a CLAUDE.md instruction.
3. **Multi-tool support.** claude-mem works across 6 tools. claude-lives is Claude Code only.
4. **Community.** 46K stars + 109 contributors vs new project.

### Ecosystem Risk

Claude Code's native Auto Memory (v2.1.59+) could eventually add isolation, search, and session management. If that happens, all third-party plugins become redundant. claude-lives' markdown storage is the easiest to migrate away from.

---

## 4. Team / Multi-Session Analysis

### The CLAUDE.md Conflict Problem (CRITICAL)

In a shared repo, every developer injects their personal memory into CLAUDE.md between markers. This means:
- Merge conflicts on every commit
- Developer A's handover notes overwrite B's
- Personal `~/.claude-lives/` paths are meaningless to teammates

**Solution:** Move injection from `CLAUDE.md` to a gitignored `.claude-lives-local.md`. Keep CLAUDE.md for team-shared project instructions. One path change in `inject_memory.sh`.

### Parallel Session Integration

**What works today:** If `.claude-life` exists and hooks are installed, any Claude session in that directory activates claude-lives automatically. File-based detection works for any session spawner.

**What breaks:** Parallel sessions write to the same files concurrently. Without isolation, last writer wins on `.last-session-meta.json`.

**Essential changes for team use:**

| Change | Why | Effort |
|--------|-----|--------|
| Inject into gitignored file, not CLAUDE.md | Merge conflicts on every commit | Small |
| `CLAUDE_LIVES_READONLY=1` env var | Automated sessions shouldn't write memory | Small |
| `flock`-based write locking | Parallel sessions corrupt files | Medium |
| `team-memory.md` in repo (committed) | Shared knowledge layer | Medium |
| `/share` command to promote facts | Move personal discoveries to team knowledge | Medium |
| `/team-init` command | Bootstrap new member with team context | Small |

### Proposed Team Architecture

```
repo/
  CLAUDE.md                  # Committed. Team instructions. No personal memory.
  team-memory.md             # Committed. Shared knowledge via /share.
  .claude-life               # Gitignored. Per-developer marker.
  .claude-lives-local.md     # Gitignored. Personal injection target.

~/.claude-lives/
  work/
    projects/
      service-a/             # Per-developer, per-project memory
        memory.md
        handover.md
        sessions/
```

### Adapted Hierarchy

```
Global (personal prefs)
  -> Life (personal identity, e.g., "work")
    -> Team Context (committed team-memory.md, read by all)
      -> Project (personal working state in ~/.claude-lives/)
```

---

## Prioritized Roadmap

### v1.6 — Security Hardening (do first)

- [ ] Validate life name from `.claude-life` with `^[a-zA-Z0-9_-]+$`
- [ ] Add `flock`-based locking to all CLAUDE.md write operations
- [ ] Make `check_injection_patterns()` block injection (not just warn)
- [ ] Fix installer Python string interpolation (use env vars)
- [ ] Validate numeric fields in stop hook JSON output
- [ ] Create `~/.claude-lives/` with 700 permissions
- [ ] Add `.gitignore` to `~/.claude-lives/` memory store

### v1.7 — Invisible Mode (Minimalist UX)

- [ ] Auto-compact: when `/save-session` detects >80% budget, compact inline instead of warning
- [ ] Reduce `/new-life` to 1-2 questions (auto-detect name, type, stack)
- [ ] Fix stale session recovery message (don't suggest /save-session when context is gone)
- [ ] Make Session Protocol more aggressive (trigger on goodbye/thanks/done phrases)
- [ ] Add `/list-lives` command for multi-life dashboard
- [ ] Hide `/cl-inject` from user-facing command list

### v2.0 — Team & Nanoclaw Support

- [ ] Move injection target from CLAUDE.md to gitignored `.claude-lives-local.md`
- [ ] Add `CLAUDE_LIVES_READONLY=1` env var for automated sessions
- [ ] Read `team-memory.md` from repo root as additional context layer
- [ ] New `/share` command to promote personal facts to team knowledge
- [ ] New `/team-init` command to seed personal memory from team context
- [ ] Session-scoped file naming for parallel session safety

### v2.1 — Power Features

- [ ] Session tagging (`/save-session --tag writing`)
- [ ] `/forget` command to remove specific facts
- [ ] `/status-all` multi-life dashboard
- [ ] Document `/sync` conflict resolution
- [ ] Auto-detect life suggestion for new project directories
