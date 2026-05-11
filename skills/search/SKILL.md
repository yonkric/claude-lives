---
description: Search across session logs, memory, and handover files
---

Full-text search across your life's memory store. Finds past decisions, facts, session context, and anything else stored in claude-lives.

## Arguments

The user provides a search query after `/search`. Examples:
- `/search authentication bug`
- `/search --all pytorch version`
- `/search --sessions-only deadline`

Flags:
- `--all` — search across ALL lives, not just the current one
- `--sessions-only` — only search session logs (skip memory/handover)
- `--memory-only` — only search memory.md and handover.md files

## Steps

1. **Detect life and project**: Find `.claude-life`, determine life name, type, and project. If `--all` is used, skip life detection and search everything.

2. **Determine search scope**: Build list of directories to search:

   **Default (current life/project):**
   - Flat life: `~/.claude-lives/{life}/` (memory.md, handover.md, sessions/*.md, archive/*.md)
   - Workspace project: `~/.claude-lives/{life}/projects/{project}/` (memory.md, handover.md, sessions/*.md, archive/*.md) AND `~/.claude-lives/{life}/memory.md` (life-level context)
   - Always include: `~/.claude-lives/global/memory.md`

   **With `--all`:**
   - `~/.claude-lives/` (all lives, all projects, all sessions)

3. **Execute search**: Use `grep` (or `rg` if available) to find matches:

   ```bash
   # Prefer rg if available, fall back to grep
   if command -v rg &>/dev/null; then
       rg --no-heading --line-number --color=never -i "{query}" {search_paths} --glob '*.md'
   else
       grep -rn -i "{query}" {search_paths} --include='*.md'
   fi
   ```

   Strip the `~/.claude-lives/` prefix from paths for readability.

4. **Format results**: Group by file and show context:

   ```
   ## Search: "{query}"

   ### {life}/sessions/2026-05-07-001.md (3 matches)
   - L12: Fixed authentication bug in login flow
   - L28: Decision: switch from JWT to session cookies for auth
   - L35: Key finding: auth middleware was caching stale tokens

   ### {life}/memory.md (1 match)
   - L8: - Auth uses session cookies (switched from JWT May 7)

   ### global/memory.md (0 matches)

   **{N} total matches across {M} files**
   ```

   If no matches: "No results for '{query}'. Try broader terms or `--all` to search across all lives."

5. **Offer follow-up**: If matches are found in session logs, offer: "Want me to read the full session log for any of these?"

## Tips shown to user

- Search is case-insensitive by default
- Use `--all` to search across every life (useful for "did I solve this before?")
- Session logs are the richest source — they capture decisions, findings, and context
- Archived sessions in `archive/` are also searched

$ARGUMENTS
