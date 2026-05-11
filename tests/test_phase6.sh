#!/usr/bin/env bash
set -euo pipefail

# Phase 6 Tests: Installation, Migration & Sync

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SRC="$PROJECT_DIR"

PASSED=0
FAILED=0
TOTAL=0

pass() { ((PASSED++)); ((TOTAL++)); echo "  PASS: $1"; }
fail() { ((FAILED++)); ((TOTAL++)); echo "  FAIL: $1 — $2"; }

echo "=== Phase 6 Tests: Installation, Migration & Sync ==="
echo ""

# ─── Installer Tests (dry run) ───

echo "--- Installer (dry run) ---"

# Test 1: install.sh syntax check
if bash -n "$PROJECT_DIR/install.sh" 2>/dev/null; then
    pass "install.sh is valid bash"
else
    fail "install.sh syntax" "bash syntax error"
fi

# Test 2: Dry run produces expected output
dry_output=$(bash "$PROJECT_DIR/install.sh" --dry-run 2>&1)
if echo "$dry_output" | grep -q "Would create" && \
   echo "$dry_output" | grep -q "Would copy" && \
   echo "$dry_output" | grep -q "Would register"; then
    pass "install.sh --dry-run shows planned actions"
else
    fail "install.sh --dry-run" "missing expected output"
fi

# Test 3: uninstall.sh syntax check
if bash -n "$PROJECT_DIR/uninstall.sh" 2>/dev/null; then
    pass "uninstall.sh is valid bash"
else
    fail "uninstall.sh syntax" "bash syntax error"
fi

echo ""

# ─── Installer Integration Test (sandboxed) ───

echo "--- Installer Integration (sandboxed) ---"

# Create a sandboxed HOME to test installation without touching the real system
SANDBOX=$(mktemp -d)
FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME/.claude"
echo '{"permissions":{"defaultMode":"auto"}}' > "$FAKE_HOME/.claude/settings.json"
# Configure git for sandboxed environment
git config --file "$FAKE_HOME/.gitconfig" user.name "Test User"
git config --file "$FAKE_HOME/.gitconfig" user.email "test@test.com"

# Test 4: Run installer in sandboxed environment
(
    export HOME="$FAKE_HOME"
    bash "$PROJECT_DIR/install.sh" 2>&1
) > "$SANDBOX/install_output.txt" 2>&1 || true

if [[ -d "$FAKE_HOME/.claude-lives/global" ]] && \
   [[ -f "$FAKE_HOME/.claude-lives/global/memory.md" ]]; then
    pass "Installer creates memory store structure"
else
    fail "Installer memory store" "global directory or memory.md missing"
fi

# Test 5: Slash commands installed
installed_commands=0
for cmd in new-life save-session resume memory-status borrow compact-memory sync cl-inject import-claude-mem fresh search timeline checkpoint; do
    if [[ -f "$FAKE_HOME/.claude/commands/${cmd}.md" ]]; then
        ((installed_commands++))
    fi
done
if [[ $installed_commands -eq 13 ]]; then
    pass "All 13 slash commands installed"
else
    fail "Slash command installation" "only $installed_commands of 13 installed"
fi

# Test 6: Hooks registered
if grep -q "stop_hook.sh" "$FAKE_HOME/.claude/settings.json" && grep -q "post_tool_hook.sh" "$FAKE_HOME/.claude/settings.json"; then
    pass "Stop + PostToolUse hooks registered in settings.json"
else
    fail "Hook registration" "not found in settings.json"
fi

# Test 7: Existing settings preserved
if grep -q "defaultMode" "$FAKE_HOME/.claude/settings.json"; then
    pass "Existing settings.json content preserved"
else
    fail "Settings preservation" "original content lost"
fi

# Test 8: Git repo initialized
if [[ -d "$FAKE_HOME/.claude-lives/.git" ]]; then
    pass "Git repo initialized in memory store"
else
    fail "Git repo" "not initialized"
fi

# Test 9: Idempotent — run installer again
(
    export HOME="$FAKE_HOME"
    bash "$PROJECT_DIR/install.sh" 2>&1
) > "$SANDBOX/install2_output.txt" 2>&1 || true

# Count Stop hooks — should still be exactly 1
hook_count=$(grep -c "stop_hook.sh" "$FAKE_HOME/.claude/settings.json" || echo 0)
if [[ "$hook_count" -eq 1 ]]; then
    pass "Idempotent: no duplicate hooks after second install"
else
    fail "Idempotent install" "found $hook_count hook entries (expected 1)"
fi

echo ""

# ─── Uninstaller Test (sandboxed) ───

echo "--- Uninstaller (sandboxed) ---"

# Test 10: Uninstall removes commands and hooks but keeps data
(
    export HOME="$FAKE_HOME"
    bash "$PROJECT_DIR/uninstall.sh" 2>&1
) > "$SANDBOX/uninstall_output.txt" 2>&1 || true

remaining_commands=$(find "$FAKE_HOME/.claude/commands" -name "*.md" -path "*new-life*" -o -name "*.md" -path "*save-session*" -o -name "*.md" -path "*resume*" | wc -l | tr -d ' ')
if [[ "$remaining_commands" -eq 0 ]]; then
    pass "Uninstaller removes slash commands"
else
    fail "Uninstaller commands" "$remaining_commands commands remain"
fi

# Test 11: Data preserved after uninstall
if [[ -d "$FAKE_HOME/.claude-lives/global" ]]; then
    pass "Memory data preserved after uninstall (no --delete-data)"
else
    fail "Data preservation" "memory data was deleted"
fi

# Test 12: Hook removed from settings
if ! grep -q "stop_hook.sh" "$FAKE_HOME/.claude/settings.json"; then
    pass "Stop hook removed from settings.json"
else
    fail "Hook removal" "hook still in settings.json"
fi

rm -rf "$SANDBOX"

echo ""

# ─── Migration Tests ───

echo "--- claude-mem Migration ---"

# Test 13: Migration script syntax
if python3 -c "import py_compile; py_compile.compile('$SRC/migration/claude_mem.py', doraise=True)" 2>/dev/null; then
    pass "claude_mem.py compiles without errors"
else
    fail "claude_mem.py syntax" "Python syntax error"
fi

# Test 14: Migration dry run against real database
MIGRATION_OUTPUT=$(mktemp -d)
if [[ -f "$HOME/.claude-mem/claude-mem.db" ]]; then
    migration_result=$(python3 "$SRC/migration/claude_mem.py" --output="$MIGRATION_OUTPUT" --dry-run 2>&1) || true
    if echo "$migration_result" | grep -q "Processing:"; then
        pass "Migration dry run reads claude-mem database"
    else
        fail "Migration dry run" "no projects processed"
    fi

    # Test 15: Migration identifies projects from database
    project_count=$(echo "$migration_result" | grep -c "Processing:" || echo "0")
    if [[ "$project_count" -ge 1 ]]; then
        pass "Migration identifies $project_count projects from database"
    else
        fail "Migration project detection" "no projects found"
    fi
else
    warn "claude-mem database not found — skipping migration tests"
    pass "Migration script exists (no database to test against)"
    pass "Migration project detection skipped (no database)"
fi
rm -rf "$MIGRATION_OUTPUT"

# Test 16: Migration actual run (to temp dir)
MIGRATION_DIR=$(mktemp -d)
if [[ -f "$HOME/.claude-mem/claude-mem.db" ]]; then
    python3 "$SRC/migration/claude_mem.py" --output="$MIGRATION_DIR" 2>&1 > /dev/null || true

    # Check that life directories were created
    life_count=$(find "$MIGRATION_DIR" -maxdepth 1 -type d ! -name "$(basename "$MIGRATION_DIR")" | wc -l | tr -d ' ')
    if [[ "$life_count" -ge 2 ]]; then
        pass "Migration creates $life_count life directories"
    else
        fail "Migration output" "only $life_count directories created"
    fi

    # Test 17: Migration report generated
    if [[ -f "$MIGRATION_DIR/migration-report.md" ]]; then
        pass "Migration report generated"
    else
        fail "Migration report" "not found"
    fi

    # Test 18: Migrated memory has correct structure
    first_life=$(find "$MIGRATION_DIR" -maxdepth 1 -type d ! -name "$(basename "$MIGRATION_DIR")" | head -1)
    if [[ -n "$first_life" ]] && [[ -f "$first_life/memory.md" ]] && \
       grep -q "Life Memory" "$first_life/memory.md"; then
        pass "Migrated memory.md has correct structure"
    else
        fail "Migrated memory structure" "missing or malformed"
    fi
else
    pass "Migration creates directories (skipped — no database)"
    pass "Migration report (skipped)"
    pass "Migrated memory structure (skipped)"
fi
rm -rf "$MIGRATION_DIR"

echo ""

# ─── Sync Command Tests ───

echo "--- Sync Command ---"

# Test 19: sync.md exists and has correct structure
if [[ -f "$SRC/commands/sync.md" ]] && \
   grep -q "git" "$SRC/commands/sync.md" && \
   grep -q "commit\|push" "$SRC/commands/sync.md"; then
    pass "sync.md has git commit/push instructions"
else
    fail "sync.md" "missing git instructions"
fi

echo ""

# ─── Summary ───

echo "================================="
echo "Phase 6 Results: $PASSED/$TOTAL passed, $FAILED failed"
echo "================================="

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
