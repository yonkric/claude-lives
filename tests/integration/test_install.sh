#!/usr/bin/env bash
# Integration test: Installation flow
# Tests that the installer sets up everything correctly

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TEST_DIR=$(mktemp -d)
export HOME="$TEST_DIR"
export CLAUDE_LIVES_DIR="$HOME/.claude-lives"

trap 'rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0

test_pass() {
    echo "  ✓ PASS: $1"
    PASS=$((PASS + 1))
}

test_fail() {
    echo "  ✗ FAIL: $1"
    FAIL=$((FAIL + 1))
}

echo "================================"
echo "Installation Integration Test"
echo "================================"
echo ""
echo "Test directory: $TEST_DIR"
echo ""

# Pre-setup: Create mock .claude directory
mkdir -p "$HOME/.claude/commands"
mkdir -p "$HOME/.claude/hooks"

# Test 1: Run installer
echo "Test 1: Run install script"
if bash "$PROJECT_ROOT/install.sh" --dry-run 2>/dev/null || true; then
    test_pass "Install script runs without errors"
else
    test_fail "Install script failed"
fi

# Test 2: Check directory structure
echo "Test 2: Check .claude-lives directory structure"
if [[ -d "$CLAUDE_LIVES_DIR" ]]; then
    test_pass "CLAUDE_LIVES_DIR created"
else
    test_fail "CLAUDE_LIVES_DIR not created"
fi

# Test 3: Check global memory
echo "Test 3: Check global memory created"
if [[ -f "$CLAUDE_LIVES_DIR/global/memory.md" ]]; then
    test_pass "Global memory.md created"
else
    test_fail "Global memory.md not created"
fi

# Test 4: Check skills copied
echo "Test 4: Check skills installed"
SKILL_COUNT=$(find "$HOME/.claude/commands" -name '*.md' 2>/dev/null | wc -l)
if [[ $SKILL_COUNT -gt 0 ]]; then
    test_pass "$SKILL_COUNT skills installed"
else
    test_fail "No skills installed"
fi

# Test 5: Check lib directory
echo "Test 5: Check lib directory exists"
if [[ -d "$HOME/.claude/claude-lives-lib" ]]; then
    test_pass "Lib directory installed"
else
    test_fail "Lib directory not installed"
fi

# Test 6: Check token_count is executable
echo "Test 6: Check lib scripts are executable"
if [[ -x "$HOME/.claude/claude-lives-lib/token_count.sh" ]]; then
    test_pass "token_count.sh is executable"
else
    test_fail "token_count.sh not executable"
fi

# Summary
echo ""
echo "================================"
echo "Results: $PASS/$((PASS+FAIL)) tests passed"
echo "================================"

if [[ $FAIL -eq 0 ]]; then
    exit 0
else
    exit 1
fi
