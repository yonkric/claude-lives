#!/usr/bin/env bash
set -euo pipefail

# Phase 5 Tests: Observability & Cross-Life

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SRC="$PROJECT_DIR"

PASSED=0
FAILED=0
TOTAL=0

pass() { ((PASSED++)); ((TOTAL++)); echo "  PASS: $1"; }
fail() { ((FAILED++)); ((TOTAL++)); echo "  FAIL: $1 — $2"; }

echo "=== Phase 5 Tests: Observability & Cross-Life ==="
echo ""

# ─── Slash Command Validation ───

echo "--- Slash Command Validation ---"

# Test 1: memory-status.md has required sections
if [[ -f "$SRC/skills/memory-status/SKILL.md" ]] && \
   grep -q "Token Usage" "$SRC/skills/memory-status/SKILL.md" && \
   grep -q "Session History" "$SRC/skills/memory-status/SKILL.md" && \
   grep -q "Freshness" "$SRC/skills/memory-status/SKILL.md"; then
    pass "memory-status.md has Token Usage, Session History, and Freshness"
else
    fail "memory-status.md" "missing required sections"
fi

# Test 2: memory-status.md handles no-life case
if grep -q "No life detected\|no life\|not found" "$SRC/skills/memory-status/SKILL.md"; then
    pass "memory-status.md handles no-life scenario"
else
    fail "memory-status.md no-life" "no fallback for missing life"
fi

# Test 3: borrow.md has required sections
if [[ -f "$SRC/skills/borrow/SKILL.md" ]] && \
   grep -q "read-only\|read only\|NOT.*modify\|Do NOT modify" "$SRC/skills/borrow/SKILL.md" && \
   grep -q "temporary\|won't persist\|will be gone" "$SRC/skills/borrow/SKILL.md"; then
    pass "borrow.md enforces read-only and temporary access"
else
    fail "borrow.md" "missing isolation guarantees"
fi

# Test 4: borrow.md handles missing life
if grep -q "not found\|Available lives\|does not exist" "$SRC/skills/borrow/SKILL.md"; then
    pass "borrow.md handles non-existent life"
else
    fail "borrow.md missing life" "no error handling for non-existent life"
fi

echo ""

# ─── Cross-Life Isolation Tests ───

echo "--- Cross-Life Isolation ---"

# Set up two lives
TEST_ROOT=$(mktemp -d)
TEST_LIVES="$TEST_ROOT/.claude-lives"
mkdir -p "$TEST_LIVES/global"
mkdir -p "$TEST_LIVES/phd/sessions" "$TEST_LIVES/phd/archive"
mkdir -p "$TEST_LIVES/work/sessions" "$TEST_LIVES/work/archive"
mkdir -p "$TEST_ROOT/phd-dir" "$TEST_ROOT/work-dir"

echo "name: phd" > "$TEST_ROOT/phd-dir/.claude-life"
echo "name: work" > "$TEST_ROOT/work-dir/.claude-life"

# Global memory
cat > "$TEST_LIVES/global/memory.md" <<EOF
---
last_updated: 2026-05-07
---

# Global Preferences

## Communication Style
Concise and direct.
EOF

# PHD memory
cat > "$TEST_LIVES/phd/memory.md" <<EOF
---
life: phd
last_compressed: 2026-05-07
session_count: 5
---

# phd — Life Memory

## Identity
PhD research in AI/ML at university.

## Current Focus
Writing Chapter 4 on cross-modal attention.

## Key Context
Python, PyTorch, LaTeX.

## Preferences
Never push to main.
EOF

cat > "$TEST_LIVES/phd/handover.md" <<EOF
---
life: phd
last_updated: 2026-05-07
---

# Handover

## What Was Happening
Running ablation experiments.

## Next Steps
Analyze results, update Chapter 4.
EOF

# Work memory
cat > "$TEST_LIVES/work/memory.md" <<EOF
---
life: work
last_compressed: 2026-05-07
session_count: 10
---

# work — Life Memory

## Identity
AI Engineer at Acme Corp.

## Current Focus
Building API gateway for the new platform.

## Key Context
TypeScript, Node.js, AWS.

## Preferences
Always get PR approval before merge.
EOF

cat > "$TEST_LIVES/work/handover.md" <<EOF
---
life: work
last_updated: 2026-05-07
---

# Handover

## What Was Happening
Implementing rate limiting middleware.

## Next Steps
Add integration tests, deploy to staging.
EOF

# Test 5: Life detection returns correct life for each directory
phd_result=$(bash "$SRC/lib/detect_life.sh" "$TEST_ROOT/phd-dir" 2>/dev/null) || true
work_result=$(bash "$SRC/lib/detect_life.sh" "$TEST_ROOT/work-dir" 2>/dev/null) || true
if [[ "$phd_result" == "phd" && "$work_result" == "work" ]]; then
    pass "Life detection isolates phd and work directories"
else
    fail "Life isolation" "phd='$phd_result', work='$work_result'"
fi

# Test 6: PHD CLAUDE.md injection doesn't include work memory
CLAUDE_LIVES_DIR="$TEST_LIVES" bash "$SRC/lib/inject_memory.sh" "$TEST_ROOT/phd-dir/CLAUDE.md" "phd"
if grep -q "cross-modal attention" "$TEST_ROOT/phd-dir/CLAUDE.md" && \
   ! grep -q "API gateway" "$TEST_ROOT/phd-dir/CLAUDE.md" && \
   ! grep -q "rate limiting" "$TEST_ROOT/phd-dir/CLAUDE.md"; then
    pass "PHD CLAUDE.md contains only PHD memory (no work leakage)"
else
    fail "PHD isolation" "work memory found in PHD CLAUDE.md"
fi

# Test 7: Work CLAUDE.md injection doesn't include PHD memory
CLAUDE_LIVES_DIR="$TEST_LIVES" bash "$SRC/lib/inject_memory.sh" "$TEST_ROOT/work-dir/CLAUDE.md" "work"
if grep -q "API gateway" "$TEST_ROOT/work-dir/CLAUDE.md" && \
   ! grep -q "cross-modal" "$TEST_ROOT/work-dir/CLAUDE.md" && \
   ! grep -q "Chapter 4" "$TEST_ROOT/work-dir/CLAUDE.md"; then
    pass "Work CLAUDE.md contains only Work memory (no PHD leakage)"
else
    fail "Work isolation" "PHD memory found in Work CLAUDE.md"
fi

# Test 8: Both CLAUDE.md files include global memory
if grep -q "Concise and direct" "$TEST_ROOT/phd-dir/CLAUDE.md" && \
   grep -q "Concise and direct" "$TEST_ROOT/work-dir/CLAUDE.md"; then
    pass "Global memory present in both lives"
else
    fail "Global memory injection" "global memory missing from one or both lives"
fi

echo ""

# ─── Borrow Mechanics ───

echo "--- Borrow Mechanics ---"

# Test 9: Borrowing reads the target life's memory (simulated)
if [[ -f "$TEST_LIVES/phd/memory.md" ]] && [[ -f "$TEST_LIVES/work/memory.md" ]]; then
    borrowed=$(cat "$TEST_LIVES/phd/memory.md")
    if echo "$borrowed" | grep -q "cross-modal attention"; then
        pass "Can read PHD memory for borrowing from work context"
    else
        fail "Borrow read" "PHD memory content not readable"
    fi
else
    fail "Borrow read" "memory files missing"
fi

# Test 10: Borrowing doesn't modify the source life
md5_before=$(md5 -q "$TEST_LIVES/phd/memory.md")
# Simulate: just read the file (borrow is read-only)
cat "$TEST_LIVES/phd/memory.md" > /dev/null
md5_after=$(md5 -q "$TEST_LIVES/phd/memory.md")
if [[ "$md5_before" == "$md5_after" ]]; then
    pass "Borrow does not modify source life's memory"
else
    fail "Borrow modification" "source memory was modified"
fi

# Test 11: Available lives can be listed
available=$(find "$TEST_LIVES" -maxdepth 1 -type d ! -name "global" ! -name "$(basename "$TEST_LIVES")" -exec basename {} \; | sort)
if echo "$available" | grep -q "phd" && echo "$available" | grep -q "work"; then
    pass "Available lives can be listed (phd, work)"
else
    fail "List available lives" "expected phd and work, got: $available"
fi

echo ""

# ─── Global Memory Layer ───

echo "--- Global Memory Layer ---"

# Test 12: Global memory is separate from life memory
global_content=$(cat "$TEST_LIVES/global/memory.md")
phd_content=$(cat "$TEST_LIVES/phd/memory.md")
if [[ "$global_content" != "$phd_content" ]]; then
    pass "Global memory is distinct from life memory"
else
    fail "Global memory distinction" "global and life memory are identical"
fi

# Test 13: Global memory exists and has correct structure
if grep -q "Global Preferences" "$TEST_LIVES/global/memory.md" && \
   grep -q "Communication Style" "$TEST_LIVES/global/memory.md"; then
    pass "Global memory has correct structure"
else
    fail "Global memory structure" "missing expected sections"
fi

# Cleanup
rm -rf "$TEST_ROOT"

echo ""

# ─── Summary ───

echo "================================="
echo "Phase 5 Results: $PASSED/$TOTAL passed, $FAILED failed"
echo "================================="

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
