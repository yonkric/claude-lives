# Edge Cases Considered

## Life Detection

| Edge Case | Tested? | Expected Behavior |
|-----------|---------|-------------------|
| .claude-life in current dir | Yes (P1-T1) | Returns life name |
| Walk up 3+ levels | Yes (P1-T2) | Finds nearest ancestor's .claude-life |
| No .claude-life anywhere | Yes (P1-T3) | Exit 1, empty output |
| CLAUDE_LIFE env var set | Yes (P1-T4) | Overrides directory detection |
| CLAUDE_LIFE with special chars | Yes (Critique #24-29) | Rejected by regex validation |
| CLAUDE_LIFE with valid chars | Yes (Critique #19-23) | Accepted (alphanumeric, hyphens, underscores) |
| Nested lives (inner overrides outer) | Yes (P1-T6, T7) | Inner life takes precedence |
| .claude-life with extra YAML fields | Yes (P1-T5) | Parses name correctly |
| Symlink in directory path | No | Should follow symlinks and detect correctly |
| .claude-life with malformed YAML | No | Should fail gracefully, not crash |
| .claude-life with empty name field | No | Should treat as no life found |
| Directory with spaces in path | No | Should handle quoted paths |
| Home directory has .claude-life | No | Would make entire home a "life" — valid but unusual |

## Memory Injection

| Edge Case | Tested? | Expected Behavior |
|-----------|---------|-------------------|
| CLAUDE.md doesn't exist | Yes (P1-T18, Critique #30) | Creates new file with markers |
| CLAUDE.md exists without markers | Yes (P1-T19) | Appends markers, preserves content |
| CLAUDE.md exists with markers | Yes (P1-T20, Critique #1-2) | Replaces content atomically |
| Mismatched markers (START only) | Yes (Critique #4-5) | Removes lone marker, appends fresh pair |
| Mismatched markers (END only) | Yes (Critique #6) | Removes lone marker, appends fresh pair |
| Frontmatter with body --- rule | Yes (Critique #7-10) | Only strips first --- pair on line 1 |
| File without frontmatter | Yes (Critique #11) | Passes through unchanged |
| Atomic write (crash safety) | Yes (Critique #1-3) | mktemp + mv in same dir, no leftover temps |
| CLAUDE.md with multiple marker sets | No | Should only match the life-specific markers |
| Memory files missing (no global/memory.md) | No | Should skip missing layers gracefully |
| Very large memory (>10KB) | No | Should still inject without corruption |
| CLAUDE.md is read-only | No | Should fail with clear error |
| Concurrent writes to CLAUDE.md | No | Potential corruption (no file locking) |
| Binary content in memory files | No | Should handle or reject |

## Session Management

| Edge Case | Tested? | Expected Behavior |
|-----------|---------|-------------------|
| /save-session with no life | Described in command | Tells user "no life detected" |
| Multiple saves in one session | Described in command | Each save creates a new log file |
| Save after /clear | No | Should still detect life and save |
| Session log naming collision (>999 per day) | No | Unlikely but would fail |
| Handover.md doesn't exist | No | Should create fresh |
| Very long session (>50 messages) | No | Summary quality depends on Claude |

## Compression

| Edge Case | Tested? | Expected Behavior |
|-----------|---------|-------------------|
| Compress with no session logs | No | Should report "nothing to compress" |
| Compress with empty memory.md | No | Should create initial memory from logs |
| Memory already under budget | No | Should still run but report minimal changes |
| All facts are duplicates | No | Should result in smaller memory |
| Archive directory doesn't exist | No | Should create it |
| Monthly archive file already exists | Described in command | Should append |

## Cross-Life

| Edge Case | Tested? | Expected Behavior |
|-----------|---------|-------------------|
| Borrow non-existent life | Yes (P5-T4 validates command has handling) | Error message with available lives |
| Borrow same life | No | Should warn "already in this life" |
| Borrow while no life active | No | Should still work (read-only) |
| Two lives with overlapping directories | No | Inner .claude-life wins |

## Installation

| Edge Case | Tested? | Expected Behavior |
|-----------|---------|-------------------|
| Fresh install | Yes (P6-T4) | Creates everything |
| Re-install over existing | Yes (P6-T9) | Idempotent, no duplicates |
| Install with no settings.json | Yes (P6) | Creates minimal one |
| Install with corrupted settings.json | No | Should fail gracefully |
| Uninstall preserves data | Yes (P6-T11) | Data kept unless --delete-data |
| Partial install (disk full mid-install) | No | Could leave inconsistent state |

## Migration

| Edge Case | Tested? | Expected Behavior |
|-----------|---------|-------------------|
| claude-mem DB doesn't exist | No (checked in code) | Error message and exit |
| Empty claude-mem DB | No | Should produce empty lives |
| Very large observations (>1000 per project) | Yes (tested with real 321-obs PHD) | Truncates to last 30 facts |
| Migration over existing memory | Yes (Critique #12-14) | Backs up to .pre-migration |
| Projects with identical names | No | Would overwrite — unlikely |
| Unicode in observation text | No | Python handles this natively |
| Migration mapping file | Not tested with file | Described in code |
