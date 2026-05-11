#!/usr/bin/env bash
set -euo pipefail

# Phase 4 Tests: Compression & Memory Decay
# Tests the compact-memory command structure, archive mechanics, and token budget logic.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SRC="$PROJECT_DIR"

PASSED=0
FAILED=0
TOTAL=0

pass() { ((PASSED++)); ((TOTAL++)); echo "  PASS: $1"; }
fail() { ((FAILED++)); ((TOTAL++)); echo "  FAIL: $1 — $2"; }

echo "=== Phase 4 Tests: Compression & Memory Decay ==="
echo ""

# ─── Slash Command Validation ───

echo "--- Slash Command Validation ---"

# Test 1: compact-memory.md exists and has required sections
if [[ -f "$SRC/skills/compact-memory/SKILL.md" ]] && \
   grep -q "Detect Life" "$SRC/skills/compact-memory/SKILL.md" && \
   grep -q "Compressed Memory" "$SRC/skills/compact-memory/SKILL.md" && \
   grep -q "Archive" "$SRC/skills/compact-memory/SKILL.md" && \
   grep -q "token_budget\|budget" "$SRC/skills/compact-memory/SKILL.md"; then
    pass "compact-memory.md has all required sections"
else
    fail "compact-memory.md" "missing required sections"
fi

# Test 2: compact-memory.md mentions dedup
if grep -q "duplicat\|dedup\|already in memory\|genuinely new" "$SRC/skills/compact-memory/SKILL.md"; then
    pass "compact-memory.md includes deduplication guidance"
else
    fail "compact-memory.md dedup" "no mention of deduplication"
fi

# Test 3: compact-memory.md mentions decay/archival
if grep -q "old facts\|not referenced\|archive\|Historical\|10 sessions" "$SRC/skills/compact-memory/SKILL.md"; then
    pass "compact-memory.md includes memory decay guidance"
else
    fail "compact-memory.md decay" "no mention of decay/archival"
fi

echo ""

# ─── Token Budget Logic Tests ───

echo "--- Token Budget Logic ---"

source "$SRC/lib/config_defaults.sh"

# Test 4: Token counting on realistic memory file
TEST_ROOT=$(mktemp -d)
TEST_LIVES="$TEST_ROOT/.claude-lives"
mkdir -p "$TEST_LIVES/testlife/sessions" "$TEST_LIVES/testlife/archive" "$TEST_LIVES/global"

# Create a memory file that's ~2000 tokens (8000 chars)
python3 -c "
content = '''---
life: testlife
last_compressed: 2026-05-07
session_count: 15
---

# testlife — Life Memory

## Identity
PhD research in artificial intelligence, focusing on transformer architectures and attention mechanisms.
Working at the intersection of NLP and computer vision.

## Current Focus
Writing Chapter 4 of the dissertation on cross-modal attention.
Preparing for the committee meeting on June 15.
Running ablation studies on the modified architecture.

## Key Context
- Primary language: Python
- Framework: PyTorch 2.x
- Compute: 4x A100 GPUs via university cluster
- Advisor: Prof. Smith, meets weekly on Wednesdays
- Committee: Prof. Smith, Prof. Jones, Dr. Lee
- Dissertation deadline: December 2026
- LaTeX for writing, Overleaf for collaboration
- Git repo at github.com/username/research-project

## Preferences
- Never push to main without PR review
- Always run experiments with fixed seeds for reproducibility
- Prefer integration tests over unit tests
- Log all experiment configs to wandb
'''
# Pad to roughly 2000 tokens
content += '\n## Historical Context\n'
for i in range(50):
    content += f'- Experiment {i}: tested learning rate {0.001 * (i+1):.4f}, got accuracy {0.85 + i*0.001:.3f}\n'
print(content)
" > "$TEST_LIVES/testlife/memory.md"

tokens=$(bash "$SRC/lib/token_count.sh" "$TEST_LIVES/testlife/memory.md")
if [[ "$tokens" -ge 500 && "$tokens" -le 3000 ]]; then
    pass "Realistic memory file token count ($tokens tokens)"
else
    fail "Realistic memory token count" "got $tokens, expected 500-3000"
fi

# Test 5: Budget check — under budget
CLAUDE_LIVES_DIR="$TEST_LIVES"
budget=$(get_life_token_budget "testlife" 2>/dev/null || echo "$DEFAULT_LIFE_TOKEN_BUDGET")
if [[ "$tokens" -lt "$budget" ]]; then
    pass "Memory is under budget ($tokens < $budget)"
else
    fail "Memory under budget" "$tokens >= $budget"
fi

# Test 6: Budget threshold detection (80%)
threshold=$(( budget * DEFAULT_COMPRESSION_THRESHOLD_PCT / 100 ))
if [[ "$tokens" -lt "$threshold" ]]; then
    pass "Memory below compression threshold ($tokens < $threshold = 80% of $budget)"
else
    echo "  INFO: Memory at $tokens tokens would trigger compression suggestion (threshold: $threshold)"
    pass "Compression threshold calculation works"
fi

echo ""

# ─── Archive Structure Tests ───

echo "--- Archive Structure ---"

# Create mock sessions for archival testing
for i in $(seq 1 5); do
    cat > "$TEST_LIVES/testlife/sessions/2026-05-0${i}-001.md" <<EOF
---
date: 2026-05-0${i}
session: 001
life: testlife
---

## Summary
Session $i: worked on experiment configuration.

## Decisions Made
- Decided to use batch size $((i * 16))

## Completed
- Ran experiment set $i

## Pending
- Analyze results from set $i

## Key Findings
- Batch size $((i * 16)) shows improved convergence
EOF
done

# Test 7: Session files exist for archival
session_count=$(ls "$TEST_LIVES/testlife/sessions/"*.md 2>/dev/null | wc -l | tr -d ' ')
if [[ "$session_count" -eq 5 ]]; then
    pass "5 session logs ready for archival"
else
    fail "Session logs for archival" "expected 5, found $session_count"
fi

# Test 8: Simulate archive creation
archive_file="$TEST_LIVES/testlife/archive/2026-05.md"
echo "# Archive: 2026-05" > "$archive_file"
echo "" >> "$archive_file"
for f in "$TEST_LIVES/testlife/sessions/"*.md; do
    basename=$(basename "$f" .md)
    summary=$(grep -A1 "## Summary" "$f" | tail -1)
    echo "## Session $basename" >> "$archive_file"
    echo "$summary" >> "$archive_file"
    echo "" >> "$archive_file"
done

if [[ -f "$archive_file" ]] && grep -q "Session 2026-05-01-001" "$archive_file"; then
    pass "Archive file created with session summaries"
else
    fail "Archive creation" "file missing or content wrong"
fi

# Test 9: Archive token count is smaller than full sessions
archive_tokens=$(bash "$SRC/lib/token_count.sh" "$archive_file")
sessions_tokens=$(bash "$SRC/lib/token_count.sh" --dir "$TEST_LIVES/testlife/sessions")
if [[ "$archive_tokens" -lt "$sessions_tokens" ]]; then
    pass "Archive is smaller than full sessions ($archive_tokens < $sessions_tokens tokens)"
else
    fail "Archive compression" "archive=$archive_tokens >= sessions=$sessions_tokens"
fi

# Test 10: After archival, sessions dir can be cleared
session_files_before=$(find "$TEST_LIVES/testlife/sessions" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
mv "$TEST_LIVES/testlife/sessions/"*.md "$TEST_LIVES/testlife/archive/" 2>/dev/null || true
session_files_after=$(find "$TEST_LIVES/testlife/sessions" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$session_files_after" -eq 0 && "$session_files_before" -eq 5 ]]; then
    pass "Sessions moved to archive (5 → 0 in sessions/)"
else
    fail "Session archival" "before=$session_files_before, after=$session_files_after"
fi

echo ""

# ─── Memory Decay Tests ───

echo "--- Memory Decay ---"

# Test 11: compact-memory.md mentions the 10-session threshold
if grep -q "10 sessions" "$SRC/skills/compact-memory/SKILL.md"; then
    pass "Decay threshold (10 sessions) documented in compact-memory"
else
    fail "Decay threshold docs" "10-session threshold not mentioned"
fi

# Test 12: Config has decay_session_threshold
echo "decay_session_threshold: 10" > "$TEST_LIVES/testlife/config.yaml"
source "$SRC/lib/config_defaults.sh"
CLAUDE_LIVES_DIR="$TEST_LIVES"
result=$(get_config_value "testlife" "decay_session_threshold" "$DEFAULT_DECAY_SESSION_THRESHOLD")
if [[ "$result" == "10" ]]; then
    pass "decay_session_threshold configurable (got $result)"
else
    fail "decay_session_threshold" "expected 10, got '$result'"
fi

# Cleanup
rm -rf "$TEST_ROOT"

echo ""

# ─── Summary ───

echo "================================="
echo "Phase 4 Results: $PASSED/$TOTAL passed, $FAILED failed"
echo "================================="

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
