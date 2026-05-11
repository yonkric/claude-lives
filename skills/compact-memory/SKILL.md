---
description: Compress life memory — deduplicate, archive old facts, stay under token budget
---

Compress the current life's memory to stay within the token budget. This merges session logs into memory, removes duplicates, archives old facts, and rewrites everything in compressed telegraphic style.

## Step 1: Detect Life and Project

Find the current life by reading `.claude-life` from this directory or parent directories. If not found, say "No life detected" and stop. If the life type is `workspace` and you're in a child directory, determine the project name.

## Step 2: Gather Current State

**For flat lives**, read:
- `~/.claude-lives/{life}/memory.md` — current life memory
- `~/.claude-lives/{life}/config.yaml` — token budget config
- All files in `~/.claude-lives/{life}/sessions/` — unarchived session logs

**For workspace projects**, read:
- `~/.claude-lives/{life}/projects/{project}/memory.md` — project memory
- `~/.claude-lives/{life}/config.yaml` — token budget config
- All files in `~/.claude-lives/{life}/projects/{project}/sessions/` — unarchived session logs

Count approximate tokens in the relevant memory.md (1 token ≈ 4 characters). Report current usage vs budget.

## Step 3: Analyze Session Logs

Read all session logs in the appropriate sessions directory. For each, extract:
- New facts not already in memory.md
- Updates to existing facts (status changes, focus shifts)
- Facts that are no longer relevant (completed work, abandoned approaches)

## Step 4: Produce Compressed Memory

Write the compressed memory to the appropriate file:
- **Flat life**: `~/.claude-lives/{life}/memory.md`
- **Workspace project**: `~/.claude-lives/{life}/projects/{project}/memory.md`

The compressed memory should:

1. **Preserves the structure**: Identity, Current Focus, Key Context, Preferences sections
2. **Adds genuinely new facts** from session logs
3. **Updates changed facts** (e.g., "working on chapter 3" → "working on chapter 4")
4. **Removes completed items** that are no longer actionable context
5. **Archives old facts**: Facts not referenced or reinforced in the last 10 sessions should be moved to a "Historical Context" section at the bottom, or removed entirely if trivial
6. **Stays under budget**: The resulting memory.md should be under the configured `life_token_budget` (default 4000 tokens ≈ 16000 characters)

### Compression Style (CRITICAL)

Rewrite ALL content in **compressed telegraphic style**. This is the primary mechanism for token savings:

**Rules:**
- Drop articles (a, an, the) and filler verbs (is, are, was, were) when meaning is clear
- Use infinitive verbs: "Fix auth bug" not "Fixed the authentication bug"
- Short phrases over sentences: "PyTorch 2.1, CUDA 12.2, A100" not "We are using PyTorch version 2.1 with CUDA 12.2 on an A100 GPU"
- One fact per line, dash-prefix: `- fact here`
- Collapse redundant/overlapping facts into single lines
- No meta-commentary ("This section contains...", "The following are...")
- Abbreviate when unambiguous: "ch4" not "chapter 4", "env" not "environment", "config" not "configuration", "impl" not "implementation"
- Remove all hedging: no "probably", "might", "seems to", "I think"

**Example compression:**

Before (68 tokens):
```
## Current Focus
We have been working on the implementation of chapter 4 of the thesis,
which is about transformer architectures. The literature review section
has been completed and we are now moving on to writing the comparison
table for different attention mechanisms.
```

After (22 tokens):
```
## Current Focus
- Writing ch4: transformer architectures
- Lit review done, now writing attention mechanism comparison table
```

**Target: 40-60% reduction** from uncompressed memory. Measure before/after.

### Deduplication Rules

When merging facts:
- Identical facts → keep one
- Near-duplicate facts → merge into one, keep the more specific version
- Superseded facts (old status) → replace with new status, drop old
- Temporal facts ("meeting on Thursday") → remove if date has passed

### Relevance Scoring

For each fact, consider:
- **Recency**: referenced in last 3 sessions = high, last 10 = medium, older = low
- **Actionability**: pending tasks > completed tasks > historical context
- **Uniqueness**: facts not derivable from code/git = keep, derivable = drop

Facts scoring low on all three → archive or remove.

Update the frontmatter:
```yaml
---
life: {life_name}
last_compressed: {today's date}
session_count: {total sessions including archived}
---
```

## Step 5: Archive Session Logs

Move all processed session logs from the appropriate sessions directory to the archive:
- **Flat life**: `sessions/` → `archive/`
- **Workspace project**: `projects/{project}/sessions/` → `projects/{project}/archive/`

If an archive file for the current month already exists (`archive/YYYY-MM.md`), append to it. Otherwise create it with the session contents.

Archive format (also telegraphic):
```markdown
# Archive: {YYYY-MM}

## {date}-{seq}
{1-2 line summary only}

## {date}-{seq}
{1-2 line summary only}
```

## Step 6: Update CLAUDE.md

After compression, update the CLAUDE.md memory section using **progressive disclosure** format. Find the life's root directory (where `.claude-life` is), then update the content between `<!-- CLAUDE-LIVES:START:{life} -->` and `<!-- CLAUDE-LIVES:END -->` markers with a compact index (~500 tokens):

```
<!-- CLAUDE-LIVES:START:{life_name} -->
## Life: {life_name}

**Identity:** {1-line compressed}
**Focus:** {1-line compressed}
**Last session:** {date}
**Was doing:** {1-2 lines from handover}
**Next:** {top 3 next steps}

### Key Context
{top 5 facts, compressed}

### Global
{2-3 lines of preferences}

### Full Memory (read when needed)
- Life memory: `~/.claude-lives/{life}/memory.md`
- Handover: `~/.claude-lives/{life}/handover.md`
- Global: `~/.claude-lives/global/memory.md`
- Sessions: `~/.claude-lives/{life}/sessions/`

<!-- CLAUDE-LIVES:END -->
```

## Step 7: Report

Tell the user:
- Before: {X} tokens in memory, {N} session logs
- After: {Y} tokens in memory, logs archived
- Savings: {X-Y} tokens freed ({percentage}% reduction)
- Compression method: telegraphic rewrite + dedup + decay
- Facts added: {count}
- Facts archived/removed: {count}
- CLAUDE.md index: ~{N} tokens (progressive disclosure)
- Full memory budget: {Y}/{budget} ({percentage}%)

$ARGUMENTS
