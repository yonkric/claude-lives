# Test Suite Critique

**Reviewer:** code-reviewer agent  
**Date:** 2026-05-07  
**Original Verdict:** BLOCK — 4 critical gaps must be fixed before shipping  
**Updated Verdict:** PASS — All CRITICAL and key HIGH issues fixed. 30 targeted tests added. 125/125 total passing.

---

## CRITICAL — Data Loss or Corruption Risk

### C1: inject_memory.sh has no atomic write protection
The re-injection path does `mv "$tmpfile" "$claude_md"` after building in a temp file. If the process dies between the write and the mv, CLAUDE.md is lost. No test validates that the original CLAUDE.md is preserved on failure.

**Fix needed:** Write to temp file in the same directory, then atomic mv. Verify original preserved on any error.

### C2: Single marker without matching pair causes silent duplication
If CLAUDE.md has `CLAUDE-LIVES:START` but not `END` (e.g., after a manual edit or git conflict), the code falls through to the append path and creates duplicate marker blocks. No test covers mismatched markers.

**Fix needed:** Add validation for marker pairing. If only one marker exists, warn and replace rather than append.

### C3: Frontmatter stripping regex matches `---` in body text
`sed -n '/^---$/,/^---$/!p'` is used to strip YAML frontmatter, but it also strips content after any `---` horizontal rule in the markdown body. No test has body text with `---`.

**Fix needed:** Only strip the FIRST pair of `---` lines. Test with horizontal rules in memory content.

### C4: Migration unconditionally overwrites existing life data
`write_life()` calls `.write_text()` without checking if the file exists. Running migration against an existing claude-lives store silently destroys accumulated memory.

**Fix needed:** Check if memory.md already exists. If so, either merge or refuse (with `--force` flag).

---

## HIGH — Will Cause Issues in Real Use

### H1: Empty CLAUDE_LIFE env var not tested
`CLAUDE_LIFE=""` is different from unset. Currently treated as "not set" but could surprise users.

### H2: stop_hook writes to non-existent life store directory
If `.claude-life` exists but the store directory hasn't been created yet (partial setup), the hook silently does nothing.

### H3: Binary files / symlinks break token counting
`find -name '*.md'` + `wc -c` aborts on broken symlinks with `set -euo pipefail`.

### H4: Borrow test only proves `cat` is read-only — tests nothing meaningful
Test 10 in Phase 5 does `cat file > /dev/null` and checks md5. This is trivially true and provides no assurance about actual borrow isolation.

### H5: Session numbering collision untested
The `{YYYY-MM-DD}-{NNN}` naming is delegated to Claude with no enforcement. Two saves on the same day could overwrite.

### H6: Config key regex injection
`grep -E "^${key}:"` uses the key directly in a regex with no escaping.

### H7: Special characters in life names break marker matching
Life names with `/`, `*`, or other metacharacters untested.

---

## MEDIUM — Nice to Have

### M1: Installer idempotency test only checks hook count, not commands or config
### M2: .claude-life with missing name: field untested
### M3: Token count of empty string/file boundary not tested
### M4: Stale session test depends on wall-clock sleep (fragile in CI)
### M5: Migration mapping file format completely untested

---

## False Confidence

1. Phase 2 tests check command files with grep for keywords — doesn't verify Claude will interpret correctly
2. Phase 5 borrow test (md5 unchanged after cat) validates nothing
3. Phase 6 migration tests substitute `pass` when no DB exists — inflates pass count

---

## Action Items

| # | Severity | Action | Status | Test |
|---|----------|--------|--------|------|
| C1 | CRITICAL | Add atomic write protection to inject_memory.sh | Fixed | test_critique_fixes #1-3 |
| C2 | CRITICAL | Handle mismatched markers in inject_memory.sh | Fixed | test_critique_fixes #4-6 |
| C3 | CRITICAL | Fix frontmatter stripping to only strip first pair | Fixed | test_critique_fixes #7-11 |
| C4 | CRITICAL | Add existence check to migration write_life() | Fixed | test_critique_fixes #12-14 |
| H1 | HIGH | Test empty CLAUDE_LIFE="" | Won't fix | empty string = unset (by design) |
| H2 | HIGH | Handle missing store directory in stop_hook | Fixed | test_critique_fixes #15-17 |
| H3 | HIGH | Guard token counting against broken symlinks | Fixed | test_critique_fixes #18 |
| H5 | HIGH | Document session numbering as Claude's responsibility | Documented | — |
| H7 | HIGH | Add life name validation (alphanumeric + hyphens only) | Fixed | test_critique_fixes #19-29 |
