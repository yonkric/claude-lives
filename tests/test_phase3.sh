#!/usr/bin/env bash
set -euo pipefail

# Phase 3 Tests: Session Management
# Tests the stop hook, session file structure, and save/resume command requirements.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SRC="$PROJECT_DIR"

PASSED=0
FAILED=0
TOTAL=0

pass() { ((PASSED++)); ((TOTAL++)); echo "  PASS: $1"; }
fail() { ((FAILED++)); ((TOTAL++)); echo "  FAIL: $1 — $2"; }

echo "=== Phase 3 Tests: Session Management ==="
echo ""

# ─── Slash Command Validation ───

echo "--- Slash Command Validation ---"

# Test 1: save-session.md has required sections
if grep -q "Detect Life" "$SRC/skills/save-session/SKILL.md" && \
   grep -q "Session Summary" "$SRC/skills/save-session/SKILL.md" && \
   grep -q "Handover" "$SRC/skills/save-session/SKILL.md" && \
   grep -q "CLAUDE-LIVES:START" "$SRC/skills/save-session/SKILL.md"; then
    pass "save-session.md has all required sections"
else
    fail "save-session.md sections" "missing required sections"
fi

# Test 2: save-session.md mentions token budget
if grep -q "token_budget\|token budget\|budget" "$SRC/skills/save-session/SKILL.md"; then
    pass "save-session.md includes token budget awareness"
else
    fail "save-session.md budget" "no mention of token budget"
fi

# Test 3: resume.md has required sections
if grep -q "handover" "$SRC/skills/resume/SKILL.md" && \
   grep -q "memory" "$SRC/skills/resume/SKILL.md" && \
   grep -q "unsaved\|last-session" "$SRC/skills/resume/SKILL.md"; then
    pass "resume.md has handover, memory, and stale detection"
else
    fail "resume.md sections" "missing required sections"
fi

# Test 4: save-session.md includes session log schema
if grep -q "## Summary" "$SRC/skills/save-session/SKILL.md" && \
   grep -q "## Completed" "$SRC/skills/save-session/SKILL.md" && \
   grep -q "## Pending" "$SRC/skills/save-session/SKILL.md"; then
    pass "save-session.md defines session log schema"
else
    fail "save-session.md schema" "missing session log schema"
fi

echo ""

# ─── Stop Hook Tests ───

echo "--- Stop Hook ---"

# Test 5: Stop hook script exists and is valid bash
if bash -n "$SRC/hooks/stop_hook.sh" 2>/dev/null; then
    pass "stop_hook.sh is valid bash"
else
    fail "stop_hook.sh syntax" "bash syntax error"
fi

# Test 6: Stop hook writes .last-session when life detected
TEST_ROOT=$(mktemp -d)
TEST_LIVES="$TEST_ROOT/.claude-lives"
mkdir -p "$TEST_LIVES/testlife/sessions"
echo "name: testlife" > "$TEST_ROOT/.claude-life"

(cd "$TEST_ROOT" && CLAUDE_LIVES_DIR="$TEST_LIVES" bash "$SRC/hooks/stop_hook.sh")
if [[ -f "$TEST_LIVES/testlife/.last-session" ]]; then
    pass "Stop hook writes .last-session timestamp"
else
    fail "Stop hook .last-session" "file not created"
fi

# Test 7: .last-session contains valid ISO timestamp
ts=$(cat "$TEST_LIVES/testlife/.last-session")
if [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    pass ".last-session has valid ISO 8601 timestamp ($ts)"
else
    fail ".last-session format" "got '$ts'"
fi

# Test 8: Stop hook does nothing when no life detected
NO_LIFE_DIR=$(mktemp -d)
(cd "$NO_LIFE_DIR" && CLAUDE_LIVES_DIR="$TEST_LIVES" bash "$SRC/hooks/stop_hook.sh") && exit_code=0 || exit_code=$?
if [[ $exit_code -eq 0 ]]; then
    pass "Stop hook exits cleanly when no life detected"
else
    fail "Stop hook no-life" "exit code $exit_code"
fi

echo ""

# ─── Session File Structure Tests ───

echo "--- Session File Structure ---"

# Simulate a saved session (what /save-session would create)
SESSION_DIR="$TEST_LIVES/testlife/sessions"

create_mock_session() {
    local seq="$1"
    local date="2026-05-07"
    cat > "$SESSION_DIR/${date}-${seq}.md" <<EOF
---
date: $date
session: $seq
life: testlife
---

## Summary
Worked on feature implementation for module A.

## Decisions Made
- Chose approach B over approach A for performance reasons

## Completed
- Implemented core logic
- Added basic error handling

## Pending
- Need to add tests
- UI component not started

## Key Findings
- The API returns paginated results, need to handle that
EOF
}

# Test 9: Create mock sessions
create_mock_session "001"
create_mock_session "002"
if [[ -f "$SESSION_DIR/2026-05-07-001.md" ]] && [[ -f "$SESSION_DIR/2026-05-07-002.md" ]]; then
    pass "Session log files created with correct naming"
else
    fail "Session log naming" "files not found"
fi

# Test 10: Session log has required frontmatter
if grep -q "^date:" "$SESSION_DIR/2026-05-07-001.md" && \
   grep -q "^session:" "$SESSION_DIR/2026-05-07-001.md" && \
   grep -q "^life:" "$SESSION_DIR/2026-05-07-001.md"; then
    pass "Session log has required frontmatter fields"
else
    fail "Session log frontmatter" "missing fields"
fi

# Test 11: Session log has all sections
if grep -q "## Summary" "$SESSION_DIR/2026-05-07-001.md" && \
   grep -q "## Decisions Made" "$SESSION_DIR/2026-05-07-001.md" && \
   grep -q "## Completed" "$SESSION_DIR/2026-05-07-001.md" && \
   grep -q "## Pending" "$SESSION_DIR/2026-05-07-001.md" && \
   grep -q "## Key Findings" "$SESSION_DIR/2026-05-07-001.md"; then
    pass "Session log has all 5 required sections"
else
    fail "Session log sections" "missing sections"
fi

echo ""

# ─── Handover Structure Tests ───

echo "--- Handover Structure ---"

# Test 12: Simulated handover after save
cat > "$TEST_LIVES/testlife/handover.md" <<EOF
---
life: testlife
last_updated: 2026-05-07
---

# Handover Notes

## What Was Happening
Adding tests for module A. Had written 3 out of 5 test cases.

## Next Steps
- Finish remaining 2 test cases for module A
- Start UI component implementation
- Review PR #42

## Pending Decisions
- Whether to use library X or Y for the UI component

## Key Files Being Worked On
- src/modules/a/core.py
- tests/test_module_a.py
EOF

if grep -q "What Was Happening" "$TEST_LIVES/testlife/handover.md" && \
   grep -q "Next Steps" "$TEST_LIVES/testlife/handover.md" && \
   grep -q "Key Files" "$TEST_LIVES/testlife/handover.md"; then
    pass "Handover has all required sections"
else
    fail "Handover sections" "missing sections"
fi

echo ""

# ─── Stale Session Detection ───

echo "--- Stale Session Detection ---"

# Test 13: Detect unsaved session (last-session newer than latest log)
# Use file modification times for reliable comparison on macOS
sleep 2
touch "$TEST_LIVES/testlife/.last-session"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$TEST_LIVES/testlife/.last-session"
latest_log=$(ls -t "$SESSION_DIR"/*.md 2>/dev/null | head -1)
if [[ -n "$latest_log" ]]; then
    last_mod=$(stat -f %m "$TEST_LIVES/testlife/.last-session" 2>/dev/null || stat -c %Y "$TEST_LIVES/testlife/.last-session" 2>/dev/null)
    log_mod=$(stat -f %m "$latest_log" 2>/dev/null || stat -c %Y "$latest_log" 2>/dev/null)
    if [[ "$last_mod" -gt "$log_mod" ]]; then
        pass "Stale session detected (.last-session newer than latest log)"
    else
        fail "Stale session detection" "last_mod=$last_mod not > log_mod=$log_mod"
    fi
else
    fail "Stale session detection" "no session logs found"
fi

# Test 14: CLAUDE.md injection after session save
cat > "$TEST_LIVES/testlife/memory.md" <<EOF
---
life: testlife
last_compressed: 2026-05-07
session_count: 2
---

# testlife — Life Memory

## Identity
Test life for session management.

## Current Focus
Working on module A implementation and tests.

## Key Context
Python project, uses pytest for testing.

## Preferences
Prefer integration tests over unit tests.
EOF

# Re-create global memory for this test
mkdir -p "$TEST_LIVES/global"
cat > "$TEST_LIVES/global/memory.md" <<EOF
---
last_updated: 2026-05-07
---

# Global Preferences

## Communication Style
Direct and concise.
EOF

CLAUDE_LIVES_DIR="$TEST_LIVES" bash "$SRC/lib/inject_memory.sh" "$TEST_ROOT/CLAUDE.md" "testlife"
if grep -q "module A" "$TEST_ROOT/CLAUDE.md" && \
   grep -q "Handover" "$TEST_ROOT/CLAUDE.md" && \
   grep -q "Direct and concise" "$TEST_ROOT/CLAUDE.md"; then
    pass "CLAUDE.md injection contains memory + handover + global after save"
else
    fail "CLAUDE.md injection after save" "missing content"
fi

# Cleanup
rm -rf "$TEST_ROOT" "$NO_LIFE_DIR"

echo ""

# ─── Summary ───

echo "================================="
echo "Phase 3 Results: $PASSED/$TOTAL passed, $FAILED failed"
echo "================================="

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
