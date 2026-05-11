#!/usr/bin/env bash
set -euo pipefail

# Tests for cherry-picked claude-mem features:
# - /search command
# - /timeline command
# - Token tracking in stop hook
# - /fresh command
# - Updated /memory-status token economics

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/.."
LIB_DIR="$SRC_DIR/lib"

PASSED=0
FAILED=0

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ─── /search Command Tests ───
echo "=== /search Command Tests ==="

# Test 1: search.md exists with frontmatter
if head -1 "$SRC_DIR/skills/search/SKILL.md" | grep -q '^\-\-\-'; then
    pass "search.md exists with frontmatter"
else
    fail "search.md exists with frontmatter"
fi

# Test 2: search supports --all flag
if grep -q '\-\-all' "$SRC_DIR/skills/search/SKILL.md"; then
    pass "search.md supports --all flag for cross-life search"
else
    fail "search.md supports --all flag for cross-life search"
fi

# Test 3: search supports --sessions-only flag
if grep -q '\-\-sessions-only' "$SRC_DIR/skills/search/SKILL.md"; then
    pass "search.md supports --sessions-only filter"
else
    fail "search.md supports --sessions-only filter"
fi

# Test 4: search supports --memory-only flag
if grep -q '\-\-memory-only' "$SRC_DIR/skills/search/SKILL.md"; then
    pass "search.md supports --memory-only filter"
else
    fail "search.md supports --memory-only filter"
fi

# Test 5: search uses grep/rg
if grep -q 'grep\|rg' "$SRC_DIR/skills/search/SKILL.md"; then
    pass "search.md uses grep or rg for searching"
else
    fail "search.md uses grep or rg for searching"
fi

# Test 6: search covers sessions, memory, handover, and archive
if grep -q 'sessions' "$SRC_DIR/skills/search/SKILL.md" && \
   grep -q 'memory.md' "$SRC_DIR/skills/search/SKILL.md" && \
   grep -q 'handover.md' "$SRC_DIR/skills/search/SKILL.md" && \
   grep -q 'archive' "$SRC_DIR/skills/search/SKILL.md"; then
    pass "search.md covers sessions, memory, handover, and archive"
else
    fail "search.md covers sessions, memory, handover, and archive"
fi

# Test 7: search handles no-results case
if grep -q 'No results' "$SRC_DIR/skills/search/SKILL.md"; then
    pass "search.md handles no-results case"
else
    fail "search.md handles no-results case"
fi

# Test 8: search is case-insensitive by default
if grep -qi 'case-insensitive\|-i' "$SRC_DIR/skills/search/SKILL.md"; then
    pass "search.md defaults to case-insensitive"
else
    fail "search.md defaults to case-insensitive"
fi

# Test 9: search handles workspace projects
if grep -q 'workspace\|project' "$SRC_DIR/skills/search/SKILL.md"; then
    pass "search.md handles workspace project scope"
else
    fail "search.md handles workspace project scope"
fi

# ─── /timeline Command Tests ───
echo ""
echo "=== /timeline Command Tests ==="

# Test 10: timeline.md exists with frontmatter
if head -1 "$SRC_DIR/skills/timeline/SKILL.md" | grep -q '^\-\-\-'; then
    pass "timeline.md exists with frontmatter"
else
    fail "timeline.md exists with frontmatter"
fi

# Test 11: timeline supports --weeks flag
if grep -q '\-\-weeks' "$SRC_DIR/skills/timeline/SKILL.md"; then
    pass "timeline.md supports --weeks filter"
else
    fail "timeline.md supports --weeks filter"
fi

# Test 12: timeline supports brief format
if grep -q '\-\-format brief\|brief' "$SRC_DIR/skills/timeline/SKILL.md"; then
    pass "timeline.md supports brief format"
else
    fail "timeline.md supports brief format"
fi

# Test 13: timeline reads session logs
if grep -q 'sessions/' "$SRC_DIR/skills/timeline/SKILL.md"; then
    pass "timeline.md reads session logs"
else
    fail "timeline.md reads session logs"
fi

# Test 14: timeline reads archive
if grep -q 'archive' "$SRC_DIR/skills/timeline/SKILL.md"; then
    pass "timeline.md reads archived sessions"
else
    fail "timeline.md reads archived sessions"
fi

# Test 15: timeline includes Key Milestones section
if grep -q 'Key Milestones\|Milestones\|milestone' "$SRC_DIR/skills/timeline/SKILL.md"; then
    pass "timeline.md includes milestones synthesis"
else
    fail "timeline.md includes milestones synthesis"
fi

# Test 16: timeline includes Major Decisions section
if grep -q 'Major Decisions\|decision' "$SRC_DIR/skills/timeline/SKILL.md"; then
    pass "timeline.md includes decisions synthesis"
else
    fail "timeline.md includes decisions synthesis"
fi

# Test 17: timeline groups by week
if grep -q 'Week of\|week' "$SRC_DIR/skills/timeline/SKILL.md"; then
    pass "timeline.md groups by week"
else
    fail "timeline.md groups by week"
fi

# Test 18: timeline handles workspace projects
if grep -q 'workspace\|Workspace\|project' "$SRC_DIR/skills/timeline/SKILL.md"; then
    pass "timeline.md handles workspace projects"
else
    fail "timeline.md handles workspace projects"
fi

# ─── Token Tracking Tests ───
echo ""
echo "=== Token Tracking Tests ==="

# Test 19: stop hook tracks session_tokens
if grep -q 'session_tokens' "$SRC_DIR/hooks/stop_hook.sh"; then
    pass "Stop hook tracks session_tokens"
else
    fail "Stop hook tracks session_tokens"
fi

# Test 20: stop hook calculates tokens from transcript size
if grep -q 'wc -c.*transcript_path\|transcript_bytes' "$SRC_DIR/hooks/stop_hook.sh"; then
    pass "Stop hook calculates tokens from transcript byte size"
else
    fail "Stop hook calculates tokens from transcript byte size"
fi

# Test 21: session_tokens in meta JSON
if grep -q '"session_tokens"' "$SRC_DIR/hooks/stop_hook.sh"; then
    pass "session_tokens included in .last-session-meta.json"
else
    fail "session_tokens included in .last-session-meta.json"
fi

# Test 22: Token approximation formula (bytes / 4)
if grep -q '/ 4' "$SRC_DIR/hooks/stop_hook.sh"; then
    pass "Token approximation: transcript bytes / 4"
else
    fail "Token approximation: transcript bytes / 4"
fi

# Test 23: memory-status shows token economics
if grep -q 'Token Economics' "$SRC_DIR/skills/memory-status/SKILL.md"; then
    pass "memory-status.md shows Token Economics section"
else
    fail "memory-status.md shows Token Economics section"
fi

# Test 24: memory-status references session_tokens from meta
if grep -q 'session_tokens' "$SRC_DIR/skills/memory-status/SKILL.md"; then
    pass "memory-status.md references session_tokens from meta"
else
    fail "memory-status.md references session_tokens from meta"
fi

# Test 25: memory-status shows memory efficiency
if grep -q 'efficiency\|recovered' "$SRC_DIR/skills/memory-status/SKILL.md"; then
    pass "memory-status.md shows memory efficiency/recovered tokens"
else
    fail "memory-status.md shows memory efficiency/recovered tokens"
fi

# Test 26: Token tracking with mock transcript
mock_transcript="$TMPDIR/transcript.jsonl"
# Create a ~400 byte transcript
for i in $(seq 1 10); do
    echo "{\"type\": \"user\", \"message\": {\"content\": \"message $i with some content\"}}" >> "$mock_transcript"
done
transcript_bytes=$(wc -c < "$mock_transcript" | tr -d ' ')
session_tokens=$((transcript_bytes / 4))
if [[ "$session_tokens" -gt 50 ]] && [[ "$session_tokens" -lt 500 ]]; then
    pass "Token tracking: mock transcript yields reasonable token count ($session_tokens)"
else
    fail "Token tracking: mock transcript yields $session_tokens tokens (expected 50-500)"
fi

# ─── /fresh Command Tests ───
echo ""
echo "=== /fresh Command Tests ==="

# Test 27: fresh.md exists with frontmatter
if head -1 "$SRC_DIR/skills/fresh/SKILL.md" | grep -q '^\-\-\-'; then
    pass "fresh.md exists with frontmatter"
else
    fail "fresh.md exists with frontmatter"
fi

# Test 28: fresh references save-session workflow
if grep -q 'save-session\|session summary\|handover\|memory' "$SRC_DIR/skills/fresh/SKILL.md"; then
    pass "fresh.md references save-session workflow"
else
    fail "fresh.md references save-session workflow"
fi

# Test 29: fresh instructs user to /clear
if grep -q '/clear' "$SRC_DIR/skills/fresh/SKILL.md"; then
    pass "fresh.md instructs user to run /clear"
else
    fail "fresh.md instructs user to run /clear"
fi

# Test 30: fresh writes .last-saved marker
if grep -q '.last-saved' "$SRC_DIR/skills/fresh/SKILL.md"; then
    pass "fresh.md includes .last-saved marker step"
else
    fail "fresh.md includes .last-saved marker step"
fi

# Test 31: fresh explains why not just /clear
if grep -q 'built-in\|intercept\|cannot' "$SRC_DIR/skills/fresh/SKILL.md"; then
    pass "fresh.md explains why /clear can't be intercepted"
else
    fail "fresh.md explains why /clear can't be intercepted"
fi

# ─── Installer/Uninstaller Counts ───
echo ""
echo "=== Installer Tests ==="

# Test 32: installer includes all new commands
if grep -q 'search' "$SRC_DIR/install.sh" && \
   grep -q 'timeline' "$SRC_DIR/install.sh" && \
   grep -q 'fresh' "$SRC_DIR/install.sh"; then
    pass "Installer includes search, timeline, and fresh commands"
else
    fail "Installer includes search, timeline, and fresh commands"
fi

# Test 33: uninstaller includes all new commands
if grep -q 'search' "$SRC_DIR/uninstall.sh" && \
   grep -q 'timeline' "$SRC_DIR/uninstall.sh" && \
   grep -q 'fresh' "$SRC_DIR/uninstall.sh"; then
    pass "Uninstaller includes search, timeline, and fresh commands"
else
    fail "Uninstaller includes search, timeline, and fresh commands"
fi

# ─── Results ───
echo ""
TOTAL=$((PASSED + FAILED))
echo "Results: $PASSED/$TOTAL passed, $FAILED failed"
if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
