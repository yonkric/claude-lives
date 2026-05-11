#!/usr/bin/env bash
set -euo pipefail

# Phase 2 Tests: Life Creation & CLAUDE.md Management
# These tests verify the file structure and injection logic.
# The /new-life slash command itself is tested manually (it's a Claude prompt).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SRC="$PROJECT_DIR"

PASSED=0
FAILED=0
TOTAL=0

pass() { ((PASSED++)); ((TOTAL++)); echo "  PASS: $1"; }
fail() { ((FAILED++)); ((TOTAL++)); echo "  FAIL: $1 — $2"; }

echo "=== Phase 2 Tests: Life Creation & CLAUDE.md Management ==="
echo ""

# ─── Slash Command File Tests ───

echo "--- Slash Commands ---"

# Test 1: new-life.md exists and has frontmatter
if [[ -f "$SRC/skills/new-life/SKILL.md" ]] && grep -q "^description:" "$SRC/skills/new-life/SKILL.md"; then
    pass "new-life.md exists with frontmatter"
else
    fail "new-life.md" "missing or no frontmatter"
fi

# Test 2: cl-inject.md exists
if [[ -f "$SRC/skills/cl-inject/SKILL.md" ]] && grep -q "^description:" "$SRC/skills/cl-inject/SKILL.md"; then
    pass "cl-inject.md exists with frontmatter"
else
    fail "cl-inject.md" "missing or no frontmatter"
fi

# Test 3: new-life.md contains interview questions (reduced to 2 in v1.7)
question_count=$(grep -c "^\d\." "$SRC/skills/new-life/SKILL.md" 2>/dev/null || grep -c "^[0-9]\." "$SRC/skills/new-life/SKILL.md" 2>/dev/null || echo 0)
if [[ "$question_count" -ge 2 ]]; then
    pass "new-life.md has 2+ interview questions"
else
    fail "new-life.md interview questions" "found $question_count, expected 2+"
fi

# Test 4: new-life.md references all required file paths
for path in ".claude-life" "memory.md" "handover.md" "config.yaml" "CLAUDE.md"; do
    if ! grep -q "$path" "$SRC/skills/new-life/SKILL.md"; then
        fail "new-life.md references $path" "not mentioned"
    fi
done
pass "new-life.md references all required file paths"

echo ""

# ─── Simulated Life Creation Tests ───

echo "--- Simulated Life Creation ---"

# Simulate what /new-life would create (without running Claude)
TEST_ROOT=$(mktemp -d)
TEST_LIVES="$TEST_ROOT/.claude-lives"

simulate_life_creation() {
    local life_name="$1"
    local life_dir="$TEST_ROOT/$life_name"
    local store_dir="$TEST_LIVES/$life_name"

    mkdir -p "$life_dir"
    mkdir -p "$store_dir/sessions"
    mkdir -p "$store_dir/archive"
    mkdir -p "$TEST_LIVES/global"

    # Create .claude-life marker
    cat > "$life_dir/.claude-life" <<EOF
name: $life_name
created: 2026-05-07
description: Test life for $life_name
token_budget:
  life: 4000
  handover: 1500
EOF

    # Create memory.md
    cat > "$store_dir/memory.md" <<EOF
---
life: $life_name
last_compressed: 2026-05-07
session_count: 0
---

# $life_name — Life Memory

## Identity
This is the $life_name life context.

## Current Focus
Starting fresh.

## Key Context
Testing purposes.

## Preferences
None specified.
EOF

    # Create handover.md
    cat > "$store_dir/handover.md" <<EOF
---
life: $life_name
last_updated: 2026-05-07
---

# Handover Notes

## What Was Happening
Life just created.

## Next Steps
Ready for first session.

## Pending Decisions
(None)

## Key Files Being Worked On
(None)
EOF

    # Create config.yaml
    cat > "$store_dir/config.yaml" <<EOF
life_token_budget: 4000
handover_token_budget: 1500
compression_threshold_pct: 80
decay_session_threshold: 10
EOF

    # Create global memory if missing
    if [[ ! -f "$TEST_LIVES/global/memory.md" ]]; then
        cat > "$TEST_LIVES/global/memory.md" <<EOF
---
last_updated: 2026-05-07
---

# Global Preferences

## Communication Style
Prefer concise, direct answers.
EOF
        cat > "$TEST_LIVES/global/config.yaml" <<EOF
global_token_budget: 1000
EOF
    fi

    # Inject memory into CLAUDE.md
    CLAUDE_LIVES_DIR="$TEST_LIVES" bash "$SRC/lib/inject_memory.sh" "$life_dir/CLAUDE.md" "$life_name"
}

# Test 5: Create simulated PHD life
simulate_life_creation "phd"
if [[ -f "$TEST_ROOT/phd/.claude-life" ]]; then
    pass "PHD .claude-life created"
else
    fail "PHD .claude-life" "not found"
fi

# Test 6: Memory store structure
if [[ -d "$TEST_LIVES/phd/sessions" ]] && [[ -d "$TEST_LIVES/phd/archive" ]] && \
   [[ -f "$TEST_LIVES/phd/memory.md" ]] && [[ -f "$TEST_LIVES/phd/handover.md" ]] && \
   [[ -f "$TEST_LIVES/phd/config.yaml" ]]; then
    pass "PHD memory store has correct structure"
else
    fail "PHD memory store structure" "missing files or directories"
fi

# Test 7: CLAUDE.md created with markers
if [[ -f "$TEST_ROOT/phd/CLAUDE.md" ]] && \
   grep -q "CLAUDE-LIVES:START:phd" "$TEST_ROOT/phd/CLAUDE.md" && \
   grep -q "CLAUDE-LIVES:END" "$TEST_ROOT/phd/CLAUDE.md"; then
    pass "PHD CLAUDE.md has markers"
else
    fail "PHD CLAUDE.md markers" "missing"
fi

# Test 8: CLAUDE.md contains memory content
if grep -q "phd life context" "$TEST_ROOT/phd/CLAUDE.md"; then
    pass "PHD CLAUDE.md contains life memory"
else
    fail "PHD CLAUDE.md content" "life memory not found"
fi

# Test 9: Global memory created
if [[ -f "$TEST_LIVES/global/memory.md" ]] && [[ -f "$TEST_LIVES/global/config.yaml" ]]; then
    pass "Global memory files created"
else
    fail "Global memory files" "missing"
fi

# Test 10: Create second life (tutor)
simulate_life_creation "tutor"
if [[ -f "$TEST_ROOT/tutor/.claude-life" ]] && [[ -f "$TEST_LIVES/tutor/memory.md" ]]; then
    pass "Second life (tutor) created alongside first"
else
    fail "Second life creation" "files missing"
fi

# Test 11: Lives are isolated — different memory content
phd_mem=$(cat "$TEST_LIVES/phd/memory.md")
tutor_mem=$(cat "$TEST_LIVES/tutor/memory.md")
if [[ "$phd_mem" != "$tutor_mem" ]]; then
    pass "PHD and Tutor memories are different"
else
    fail "Memory isolation" "PHD and Tutor have identical memory"
fi

# Test 12: Detection works from subdirectory of created life
phd_result=$(bash "$SRC/lib/detect_life.sh" "$TEST_ROOT/phd" 2>/dev/null) || true
tutor_result=$(bash "$SRC/lib/detect_life.sh" "$TEST_ROOT/tutor" 2>/dev/null) || true
if [[ "$phd_result" == "phd" ]] && [[ "$tutor_result" == "tutor" ]]; then
    pass "Life detection works for both created lives"
else
    fail "Life detection for created lives" "phd='$phd_result', tutor='$tutor_result'"
fi

echo ""

# ─── CLAUDE.md Preservation Tests ───

echo "--- CLAUDE.md Preservation ---"

# Test 13: Existing CLAUDE.md content preserved
PRESERVE_DIR=$(mktemp -d)
mkdir -p "$TEST_LIVES/preserve"
cat > "$PRESERVE_DIR/CLAUDE.md" <<EOF
# My Existing Project

## Build Commands
npm run build
npm test

## Important Notes
Do not modify the config directory.
EOF

echo "name: preserve" > "$PRESERVE_DIR/.claude-life"
cat > "$TEST_LIVES/preserve/memory.md" <<EOF
---
life: preserve
---

# preserve — Life Memory

## Identity
Test preservation life.
EOF
cat > "$TEST_LIVES/preserve/handover.md" <<EOF
---
life: preserve
---

# Handover
Nothing to hand over.
EOF

CLAUDE_LIVES_DIR="$TEST_LIVES" bash "$SRC/lib/inject_memory.sh" "$PRESERVE_DIR/CLAUDE.md" "preserve"

if grep -q "My Existing Project" "$PRESERVE_DIR/CLAUDE.md" && \
   grep -q "npm run build" "$PRESERVE_DIR/CLAUDE.md" && \
   grep -q "Do not modify" "$PRESERVE_DIR/CLAUDE.md" && \
   grep -q "CLAUDE-LIVES:START" "$PRESERVE_DIR/CLAUDE.md"; then
    pass "Existing CLAUDE.md content fully preserved after injection"
else
    fail "CLAUDE.md preservation" "some content lost"
fi

# Test 14: Re-injection after content changes
cat > "$TEST_LIVES/preserve/memory.md" <<EOF
---
life: preserve
---

# preserve — Life Memory

## Identity
UPDATED: Now working on something new.
EOF

CLAUDE_LIVES_DIR="$TEST_LIVES" bash "$SRC/lib/inject_memory.sh" "$PRESERVE_DIR/CLAUDE.md" "preserve"

if grep -q "My Existing Project" "$PRESERVE_DIR/CLAUDE.md" && \
   grep -q "UPDATED: Now working on something new" "$PRESERVE_DIR/CLAUDE.md" && \
   ! grep -q "Test preservation life" "$PRESERVE_DIR/CLAUDE.md"; then
    pass "Re-injection updates memory but preserves project content"
else
    fail "Re-injection preservation" "content mismatch"
fi

# Cleanup
rm -rf "$TEST_ROOT" "$PRESERVE_DIR"

echo ""

# ─── Summary ───

echo "================================="
echo "Phase 2 Results: $PASSED/$TOTAL passed, $FAILED failed"
echo "================================="

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
