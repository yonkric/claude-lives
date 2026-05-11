#!/usr/bin/env bash
set -euo pipefail

# Phase 1 Tests: Foundation — Life detection, token counting, templates
# Run from project root: bash tests/test_phase1.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SRC="$PROJECT_DIR"

PASSED=0
FAILED=0
TOTAL=0

pass() { ((PASSED++)); ((TOTAL++)); echo "  PASS: $1"; }
fail() { ((FAILED++)); ((TOTAL++)); echo "  FAIL: $1 — $2"; }

echo "=== Phase 1 Tests: Foundation ==="
echo ""

# ─── Life Detection Tests ───

echo "--- Life Detection ---"

# Test 1: Detect life in current dir
TEST_DIR=$(mktemp -d)
echo "name: testlife" > "$TEST_DIR/.claude-life"
echo "created: 2026-05-07" >> "$TEST_DIR/.claude-life"
result=$(bash "$SRC/lib/detect_life.sh" "$TEST_DIR" 2>/dev/null) || true
if [[ "$result" == "testlife" ]]; then
    pass "Detect life in current directory"
else
    fail "Detect life in current directory" "expected 'testlife', got '$result'"
fi

# Test 2: Walk up directories
DEEP_DIR="$TEST_DIR/sub/deep/nested"
mkdir -p "$DEEP_DIR"
result=$(bash "$SRC/lib/detect_life.sh" "$DEEP_DIR" 2>/dev/null) || true
if [[ "$result" == "testlife" ]]; then
    pass "Walk up directories"
else
    fail "Walk up directories" "expected 'testlife', got '$result'"
fi

# Test 3: No life found
EMPTY_DIR=$(mktemp -d)
result=$(bash "$SRC/lib/detect_life.sh" "$EMPTY_DIR" 2>/dev/null) && exit_code=0 || exit_code=$?
if [[ $exit_code -ne 0 && -z "$result" ]]; then
    pass "No life found returns exit 1"
else
    fail "No life found returns exit 1" "exit_code=$exit_code, result='$result'"
fi

# Test 4: Environment variable override
result=$(CLAUDE_LIFE=override bash "$SRC/lib/detect_life.sh" "$EMPTY_DIR" 2>/dev/null) || true
if [[ "$result" == "override" ]]; then
    pass "CLAUDE_LIFE env var override"
else
    fail "CLAUDE_LIFE env var override" "expected 'override', got '$result'"
fi

# Test 5: Life with extra fields in .claude-life
FANCY_DIR=$(mktemp -d)
cat > "$FANCY_DIR/.claude-life" <<EOF
name: fancy
created: 2026-05-07
description: A life with extra fields
token_budget:
  life: 8000
  handover: 2000
EOF
result=$(bash "$SRC/lib/detect_life.sh" "$FANCY_DIR" 2>/dev/null) || true
if [[ "$result" == "fancy" ]]; then
    pass "Detect life with extra YAML fields"
else
    fail "Detect life with extra YAML fields" "expected 'fancy', got '$result'"
fi

# Test 6: Nested lives (inner life takes precedence)
INNER_DIR="$TEST_DIR/inner_project"
mkdir -p "$INNER_DIR"
echo "name: innerlife" > "$INNER_DIR/.claude-life"
result=$(bash "$SRC/lib/detect_life.sh" "$INNER_DIR" 2>/dev/null) || true
if [[ "$result" == "innerlife" ]]; then
    pass "Nested life: inner takes precedence"
else
    fail "Nested life: inner takes precedence" "expected 'innerlife', got '$result'"
fi

# Test 7: Subdirectory of inner life finds inner, not outer
INNER_SUB="$INNER_DIR/subdir"
mkdir -p "$INNER_SUB"
result=$(bash "$SRC/lib/detect_life.sh" "$INNER_SUB" 2>/dev/null) || true
if [[ "$result" == "innerlife" ]]; then
    pass "Nested life: subdirectory finds inner"
else
    fail "Nested life: subdirectory finds inner" "expected 'innerlife', got '$result'"
fi

# Cleanup
rm -rf "$TEST_DIR" "$EMPTY_DIR" "$FANCY_DIR"

echo ""

# ─── Token Counter Tests ───

echo "--- Token Counter ---"

# Test 8: Count tokens in a string
result=$(bash "$SRC/lib/token_count.sh" --string "hello world this is a test" 2>/dev/null)
expected=7  # 26 chars / 4 = 6.5, rounds up to 7
if [[ "$result" -ge 5 && "$result" -le 10 ]]; then
    pass "Token count string (got $result, expected ~7)"
else
    fail "Token count string" "expected ~7, got '$result'"
fi

# Test 9: Count tokens in a file
TMPFILE=$(mktemp)
echo "This is a test file with some content for token counting purposes." > "$TMPFILE"
result=$(bash "$SRC/lib/token_count.sh" "$TMPFILE" 2>/dev/null)
if [[ "$result" -ge 10 && "$result" -le 25 ]]; then
    pass "Token count file (got $result)"
else
    fail "Token count file" "expected 10-25, got '$result'"
fi
rm -f "$TMPFILE"

# Test 10: Count tokens for non-existent file
result=$(bash "$SRC/lib/token_count.sh" "/tmp/nonexistent_file_12345.md" 2>/dev/null) && exit_code=0 || exit_code=$?
if [[ "$result" == "0" ]]; then
    pass "Token count non-existent file returns 0"
else
    fail "Token count non-existent file" "expected '0', got '$result'"
fi

# Test 11: Count tokens in directory
TMPDIR=$(mktemp -d)
echo "File one content here" > "$TMPDIR/a.md"
echo "File two content is longer than file one" > "$TMPDIR/b.md"
echo "This is not markdown" > "$TMPDIR/c.txt"
result=$(bash "$SRC/lib/token_count.sh" --dir "$TMPDIR" 2>/dev/null)
if [[ "$result" -ge 10 && "$result" -le 30 ]]; then
    pass "Token count directory (got $result, only .md files)"
else
    fail "Token count directory" "expected 10-30, got '$result'"
fi
rm -rf "$TMPDIR"

echo ""

# ─── Config Defaults Tests ───

echo "--- Config Defaults ---"

# Test 12: Source config defaults
source "$SRC/lib/config_defaults.sh"
if [[ "$DEFAULT_LIFE_TOKEN_BUDGET" == "4000" ]]; then
    pass "Default life token budget is 4000"
else
    fail "Default life token budget" "expected 4000, got '$DEFAULT_LIFE_TOKEN_BUDGET'"
fi

# Test 13: Default global budget
if [[ "$DEFAULT_GLOBAL_TOKEN_BUDGET" == "1000" ]]; then
    pass "Default global token budget is 1000"
else
    fail "Default global token budget" "expected 1000, got '$DEFAULT_GLOBAL_TOKEN_BUDGET'"
fi

# Test 14: Config override from file
OVERRIDE_DIR=$(mktemp -d)
CLAUDE_LIVES_DIR="$OVERRIDE_DIR"
mkdir -p "$OVERRIDE_DIR/testlife"
echo "life_token_budget: 8000" > "$OVERRIDE_DIR/testlife/config.yaml"
result=$(get_life_token_budget "testlife")
if [[ "$result" == "8000" ]]; then
    pass "Config override from file (8000)"
else
    fail "Config override from file" "expected 8000, got '$result'"
fi

# Test 15: Config fallback to default
result=$(get_life_token_budget "nonexistent")
if [[ "$result" == "4000" ]]; then
    pass "Config fallback to default (4000)"
else
    fail "Config fallback to default" "expected 4000, got '$result'"
fi
rm -rf "$OVERRIDE_DIR"

echo ""

# ─── Template Tests ───

echo "--- Templates ---"

# Test 16: Templates exist
templates=("claude-life.yaml" "life-config.yaml" "memory.md" "handover.md" "global-memory.md" "global-config.yaml")
all_exist=true
for t in "${templates[@]}"; do
    if [[ ! -f "$SRC/templates/$t" ]]; then
        all_exist=false
        fail "Template $t exists" "file not found"
    fi
done
if $all_exist; then
    pass "All 6 templates exist"
fi

# Test 17: Templates have placeholders
if grep -q '{{LIFE_NAME}}' "$SRC/templates/claude-life.yaml"; then
    pass "claude-life.yaml has {{LIFE_NAME}} placeholder"
else
    fail "claude-life.yaml placeholders" "missing {{LIFE_NAME}}"
fi

if grep -q '{{IDENTITY}}' "$SRC/templates/memory.md"; then
    pass "memory.md has {{IDENTITY}} placeholder"
else
    fail "memory.md placeholders" "missing {{IDENTITY}}"
fi

echo ""

# ─── Inject Memory Tests ───

echo "--- Memory Injection ---"

# Test 18: Inject into new file
INJECT_DIR=$(mktemp -d)
CLAUDE_LIVES_DIR="$INJECT_DIR/.claude-lives"
mkdir -p "$CLAUDE_LIVES_DIR/global"
mkdir -p "$CLAUDE_LIVES_DIR/testlife"
echo -e "---\nlast_updated: 2026-05-07\n---\n# Global\nPrefer concise answers." > "$CLAUDE_LIVES_DIR/global/memory.md"
echo -e "---\nlife: testlife\n---\n# Test Memory\nWorking on feature X." > "$CLAUDE_LIVES_DIR/testlife/memory.md"
echo -e "---\nlife: testlife\n---\n# Handover\nNext: finish feature X tests." > "$CLAUDE_LIVES_DIR/testlife/handover.md"

target="$INJECT_DIR/CLAUDE.md"
CLAUDE_LIVES_DIR="$CLAUDE_LIVES_DIR" bash "$SRC/lib/inject_memory.sh" "$target" "testlife" --full
if grep -q "CLAUDE-LIVES:START:testlife" "$target" && grep -q "CLAUDE-LIVES:END" "$target"; then
    pass "Inject into new file (markers present)"
else
    fail "Inject into new file" "markers not found"
fi

if grep -q "Working on feature X" "$target"; then
    pass "Inject includes life memory content"
else
    fail "Inject includes life memory" "content not found"
fi

if grep -q "Prefer concise answers" "$target"; then
    pass "Inject includes global memory content"
else
    fail "Inject includes global memory" "content not found"
fi

# Test 19: Inject preserves existing content
echo "# My Project" > "$INJECT_DIR/CLAUDE2.md"
echo "" >> "$INJECT_DIR/CLAUDE2.md"
echo "This is my existing project documentation." >> "$INJECT_DIR/CLAUDE2.md"
CLAUDE_LIVES_DIR="$CLAUDE_LIVES_DIR" bash "$SRC/lib/inject_memory.sh" "$INJECT_DIR/CLAUDE2.md" "testlife" --full
if grep -q "My Project" "$INJECT_DIR/CLAUDE2.md" && grep -q "CLAUDE-LIVES:START" "$INJECT_DIR/CLAUDE2.md"; then
    pass "Inject preserves existing CLAUDE.md content"
else
    fail "Inject preserves existing content" "original content lost"
fi

# Test 20: Re-inject updates life memory content
echo -e "---\nlife: testlife\n---\n# Test Memory\nNow working on feature Y instead." > "$CLAUDE_LIVES_DIR/testlife/memory.md"
echo -e "---\nlife: testlife\n---\n# Handover\nNext: finish feature Y tests." > "$CLAUDE_LIVES_DIR/testlife/handover.md"
CLAUDE_LIVES_DIR="$CLAUDE_LIVES_DIR" bash "$SRC/lib/inject_memory.sh" "$target" "testlife" --full
if grep -q "feature Y" "$target" && ! grep -q "feature X" "$target"; then
    pass "Re-inject updates content between markers"
else
    fail "Re-inject updates content" "old content still present or new content missing"
fi

rm -rf "$INJECT_DIR"

echo ""

# ─── Summary ───

echo "================================="
echo "Phase 1 Results: $PASSED/$TOTAL passed, $FAILED failed"
echo "================================="

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
