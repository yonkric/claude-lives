#!/usr/bin/env bash
set -euo pipefail

# Tests for critique fixes: C1 (atomic writes), C2 (mismatched markers),
# C3 (frontmatter stripping), C4 (migration backup), H2 (stop hook mkdir),
# H3 (symlink exclusion), H7 (life name validation)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/.."
LIB_DIR="$SRC_DIR/lib"

PASSED=0
FAILED=0

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== Critique Fix Tests ==="
echo ""

# --- C1: Atomic Writes ---
echo "--- C1: Atomic Writes ---"

# Set up a life with memory for injection
export CLAUDE_LIVES_DIR="$TMPDIR/lives-c1"
mkdir -p "$CLAUDE_LIVES_DIR/testlife/sessions" "$CLAUDE_LIVES_DIR/testlife/archive" "$CLAUDE_LIVES_DIR/global"
echo -e "---\nlife: testlife\n---\n\nTest memory content" > "$CLAUDE_LIVES_DIR/testlife/memory.md"
echo -e "---\nscope: global\n---\n\nGlobal prefs" > "$CLAUDE_LIVES_DIR/global/memory.md"

CLAUDE_MD="$TMPDIR/c1-test/CLAUDE.md"
mkdir -p "$TMPDIR/c1-test"
echo "# My Project" > "$CLAUDE_MD"
echo "Existing content here." >> "$CLAUDE_MD"

source "$LIB_DIR/inject_memory.sh"
inject_memory "$CLAUDE_MD" "testlife" --full

# Verify the file exists and has content (atomic write succeeded)
if [[ -f "$CLAUDE_MD" ]] && grep -q "CLAUDE-LIVES:START:testlife" "$CLAUDE_MD" && grep -q "Existing content" "$CLAUDE_MD"; then
    pass "Atomic write preserves content and adds markers"
else
    fail "Atomic write preserves content and adds markers"
fi

# Re-inject to test the replace path (both markers exist)
echo "Updated memory content" > "$CLAUDE_LIVES_DIR/testlife/memory.md"
inject_memory "$CLAUDE_MD" "testlife" --full
if grep -q "Existing content" "$CLAUDE_MD" && grep -q "Updated memory content" "$CLAUDE_MD"; then
    pass "Atomic re-injection updates memory and preserves project content"
else
    fail "Atomic re-injection updates memory and preserves project content"
fi

# Verify no temp files left behind
leftover=$(find "$TMPDIR/c1-test" -name "*.tmp.*" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$leftover" == "0" ]]; then
    pass "No temporary files left after injection"
else
    fail "No temporary files left after injection (found $leftover)"
fi

echo ""

# --- C2: Mismatched Markers ---
echo "--- C2: Mismatched Markers ---"

export CLAUDE_LIVES_DIR="$TMPDIR/lives-c2"
mkdir -p "$CLAUDE_LIVES_DIR/mylife/sessions" "$CLAUDE_LIVES_DIR/mylife/archive" "$CLAUDE_LIVES_DIR/global"
echo -e "---\nlife: mylife\n---\n\nMylife memory" > "$CLAUDE_LIVES_DIR/mylife/memory.md"
echo -e "---\nscope: global\n---\n\nGlobal" > "$CLAUDE_LIVES_DIR/global/memory.md"

# Test: only START marker, no END
ONLY_START="$TMPDIR/c2-start.md"
cat > "$ONLY_START" <<'CONTENT'
# Project docs
Some important info.
<!-- CLAUDE-LIVES:START:mylife -->
orphaned start without end
More project stuff.
CONTENT

source "$LIB_DIR/inject_memory.sh"
inject_memory "$ONLY_START" "mylife"

start_count=$(grep -c "CLAUDE-LIVES:START:mylife" "$ONLY_START" || true)
end_count=$(grep -c "CLAUDE-LIVES:END" "$ONLY_START" || true)
if [[ "$start_count" == "1" ]] && [[ "$end_count" == "1" ]]; then
    pass "Mismatched START-only fixed to proper marker pair"
else
    fail "Mismatched START-only fixed to proper marker pair (start=$start_count, end=$end_count)"
fi

if grep -q "Some important info" "$ONLY_START" && grep -q "More project stuff" "$ONLY_START"; then
    pass "Mismatched marker fix preserves non-marker content"
else
    fail "Mismatched marker fix preserves non-marker content"
fi

# Test: only END marker, no START
ONLY_END="$TMPDIR/c2-end.md"
cat > "$ONLY_END" <<'CONTENT'
# Another project
Data here.
<!-- CLAUDE-LIVES:END -->
More data.
CONTENT

inject_memory "$ONLY_END" "mylife"
start_count=$(grep -c "CLAUDE-LIVES:START:mylife" "$ONLY_END" || true)
end_count=$(grep -c "CLAUDE-LIVES:END" "$ONLY_END" || true)
if [[ "$start_count" == "1" ]] && [[ "$end_count" == "1" ]]; then
    pass "Mismatched END-only fixed to proper marker pair"
else
    fail "Mismatched END-only fixed to proper marker pair (start=$start_count, end=$end_count)"
fi

echo ""

# --- C3: Frontmatter Stripping ---
echo "--- C3: Frontmatter Stripping ---"

# Create a memory file with frontmatter AND body --- (horizontal rule)
FMTEST="$TMPDIR/fm-test.md"
cat > "$FMTEST" <<'CONTENT'
---
life: testlife
last_compressed: 2026-05-01
---

# Memory

Important facts here.

---

## Section After Rule

More facts below the horizontal rule.
CONTENT

source "$LIB_DIR/inject_memory.sh"
result=$(strip_frontmatter "$FMTEST")

if echo "$result" | grep -q "Important facts here"; then
    pass "Frontmatter stripped: body content preserved"
else
    fail "Frontmatter stripped: body content preserved"
fi

if echo "$result" | grep -q "^---$"; then
    pass "Body horizontal rule (---) preserved after frontmatter strip"
else
    fail "Body horizontal rule (---) preserved after frontmatter strip"
fi

if echo "$result" | grep -q "last_compressed"; then
    fail "Frontmatter content leaked into output"
else
    pass "Frontmatter content removed from output"
fi

if echo "$result" | grep -q "Section After Rule"; then
    pass "Content after body horizontal rule preserved"
else
    fail "Content after body horizontal rule preserved"
fi

# Test file with NO frontmatter
NOFM="$TMPDIR/no-fm.md"
cat > "$NOFM" <<'CONTENT'
# Just a heading

Some content.

---

Below the rule.
CONTENT

result2=$(strip_frontmatter "$NOFM")
if echo "$result2" | grep -q "Just a heading" && echo "$result2" | grep -q "Below the rule"; then
    pass "File without frontmatter passes through unchanged"
else
    fail "File without frontmatter passes through unchanged"
fi

echo ""

# --- C4: Migration Backup ---
echo "--- C4: Migration Backup ---"

MIGRATION_DIR="$TMPDIR/migration-test"
mkdir -p "$MIGRATION_DIR/existing-life"
echo "# Old Memory" > "$MIGRATION_DIR/existing-life/memory.md"
echo "# Old Handover" > "$MIGRATION_DIR/existing-life/handover.md"

# Create a minimal SQLite DB for migration test
DB="$TMPDIR/test-migration.db"
python3 -c "
import sqlite3
conn = sqlite3.connect('$DB')
conn.execute('''CREATE TABLE observations (
    title TEXT, subtitle TEXT, narrative TEXT, facts TEXT,
    created_at TEXT, created_at_epoch INTEGER, project TEXT
)''')
conn.execute('''CREATE TABLE session_summaries (
    request TEXT, investigated TEXT, learned TEXT, completed TEXT,
    next_steps TEXT, notes TEXT, created_at TEXT, created_at_epoch INTEGER, project TEXT
)''')
conn.execute('''INSERT INTO observations VALUES (
    'Test', 'sub', 'narr', '[\"fact1\"]', '2026-05-01', 1746100000, 'existing-life'
)''')
conn.execute('''INSERT INTO session_summaries VALUES (
    'req', 'inv', 'learned', 'completed', 'next', 'notes', '2026-05-01', 1746100000, 'existing-life'
)''')
conn.commit()
conn.close()
"

python3 "$SRC_DIR/migration/claude_mem.py" --db="$DB" --output="$MIGRATION_DIR" 2>&1 | grep -q "BACKUP" && backup_logged=true || backup_logged=false
if [[ -f "$MIGRATION_DIR/existing-life/memory.md.pre-migration" ]]; then
    pass "Migration creates backup of existing memory.md"
else
    fail "Migration creates backup of existing memory.md"
fi

if [[ -f "$MIGRATION_DIR/existing-life/handover.md.pre-migration" ]]; then
    pass "Migration creates backup of existing handover.md"
else
    fail "Migration creates backup of existing handover.md"
fi

if grep -q "Old Memory" "$MIGRATION_DIR/existing-life/memory.md.pre-migration"; then
    pass "Backup contains original memory content"
else
    fail "Backup contains original memory content"
fi

echo ""

# --- H2: Stop Hook Creates Missing Directory ---
echo "--- H2: Stop Hook Creates Missing Directory ---"

export CLAUDE_LIVES_DIR="$TMPDIR/lives-h2"
# Do NOT create the life directory — the hook should create it
LIFE_DIR_H2="$TMPDIR/h2-project"
mkdir -p "$LIFE_DIR_H2"
echo -e "name: newlife" > "$LIFE_DIR_H2/.claude-life"

# Run stop hook from the project directory
(cd "$LIFE_DIR_H2" && bash "$SRC_DIR/hooks/stop_hook.sh" 2>/dev/null) || true

if [[ -d "$CLAUDE_LIVES_DIR/newlife" ]]; then
    pass "Stop hook creates life directory when missing"
else
    fail "Stop hook creates life directory when missing"
fi

if [[ -d "$CLAUDE_LIVES_DIR/newlife/sessions" ]] && [[ -d "$CLAUDE_LIVES_DIR/newlife/archive" ]]; then
    pass "Stop hook creates sessions/ and archive/ subdirectories"
else
    fail "Stop hook creates sessions/ and archive/ subdirectories"
fi

if [[ -f "$CLAUDE_LIVES_DIR/newlife/.last-session" ]]; then
    pass "Stop hook writes .last-session after creating directory"
else
    fail "Stop hook writes .last-session after creating directory"
fi

echo ""

# --- H3: Token Count Excludes Symlinks ---
echo "--- H3: Token Count Excludes Symlinks ---"

H3DIR="$TMPDIR/h3-test"
mkdir -p "$H3DIR"
echo "Real file content for counting" > "$H3DIR/real.md"
echo "This is a very long piece of text that should not be counted if symlinks are excluded properly" > "$TMPDIR/h3-external.md"
ln -s "$TMPDIR/h3-external.md" "$H3DIR/symlink.md"

source "$LIB_DIR/token_count.sh"
real_only=$(count_tokens_file "$H3DIR/real.md")
dir_total=$(count_tokens_dir "$H3DIR")

if [[ "$dir_total" == "$real_only" ]]; then
    pass "Token count directory excludes symlinked files"
else
    fail "Token count directory excludes symlinked files (dir=$dir_total, real=$real_only)"
fi

echo ""

# --- H7: Life Name Validation ---
echo "--- H7: Life Name Validation ---"

source "$LIB_DIR/detect_life.sh"

# Valid names
for name in "phd" "my-project" "test_life" "PHD123" "a"; do
    CLAUDE_LIFE="$name" detect_life > /dev/null 2>&1 && result=0 || result=$?
    if [[ "$result" == "0" ]]; then
        pass "Valid life name accepted: $name"
    else
        fail "Valid life name accepted: $name"
    fi
done

# Invalid names
for name in "../escape" "my life" "test;rm" 'life"quoted' "path/traverse" "" "life name"; do
    if [[ -z "$name" ]]; then
        # Empty string: CLAUDE_LIFE="" means unset, skip
        continue
    fi
    CLAUDE_LIFE="$name" detect_life > /dev/null 2>&1 && result=0 || result=$?
    if [[ "$result" != "0" ]]; then
        pass "Invalid life name rejected: $name"
    else
        fail "Invalid life name rejected: $name (was accepted)"
    fi
done

echo ""

# --- Injection into Non-Existent File ---
echo "--- Edge Case: Injection into Non-Existent File ---"

export CLAUDE_LIVES_DIR="$TMPDIR/lives-edge"
mkdir -p "$CLAUDE_LIVES_DIR/edgelife/sessions" "$CLAUDE_LIVES_DIR/edgelife/archive" "$CLAUDE_LIVES_DIR/global"
echo -e "---\nlife: edgelife\n---\n\nEdge memory" > "$CLAUDE_LIVES_DIR/edgelife/memory.md"
echo -e "---\nscope: global\n---\n\nGlobal" > "$CLAUDE_LIVES_DIR/global/memory.md"

NEW_FILE="$TMPDIR/brand-new/CLAUDE.md"
mkdir -p "$TMPDIR/brand-new"

source "$LIB_DIR/inject_memory.sh"
inject_memory "$NEW_FILE" "edgelife"

if [[ -f "$NEW_FILE" ]] && grep -q "CLAUDE-LIVES:START:edgelife" "$NEW_FILE" && grep -q "CLAUDE-LIVES:END" "$NEW_FILE"; then
    pass "Injection creates new CLAUDE.md when none exists"
else
    fail "Injection creates new CLAUDE.md when none exists"
fi

echo ""

echo "================================="
echo "Critique Fix Results: $PASSED/$((PASSED + FAILED)) passed, $FAILED failed"
echo "================================="

exit $FAILED
