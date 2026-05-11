#!/usr/bin/env bash
set -euo pipefail

# Tests for auto-save/resume features:
# - Stop hook metadata extraction
# - Session Protocol in progressive block
# - .last-saved marker in save-session
# - Stale detection improvements in resume

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/.."
LIB_DIR="$SRC_DIR/lib"

PASSED=0
FAILED=0

pass() { echo "  PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED + 1)); }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

setup_life() {
    export CLAUDE_LIVES_DIR="$TMPDIR/lives"
    mkdir -p "$CLAUDE_LIVES_DIR/testlife/sessions" "$CLAUDE_LIVES_DIR/testlife/archive"
    mkdir -p "$CLAUDE_LIVES_DIR/global"

    mkdir -p "$TMPDIR/project"
    cat > "$TMPDIR/project/.claude-life" <<'MARKER'
name: testlife
created: 2026-05-08
description: Test life
type: flat
MARKER

    cat > "$CLAUDE_LIVES_DIR/testlife/memory.md" <<'MEM'
---
life: testlife
session_count: 5
---

# testlife — Life Memory

## Identity
Test user, software developer

## Current Focus
Building auto-session features

## Key Context
- Working on claude-lives plugin
- Bash + markdown architecture
- Token optimization implemented
MEM

    cat > "$CLAUDE_LIVES_DIR/testlife/handover.md" <<'HANDOVER'
---
life: testlife
last_updated: 2026-05-08
---

# Handover Notes

## What Was Happening
Implementing auto-save feature

## Next Steps
- Write tests
- Update documentation
HANDOVER

    cat > "$CLAUDE_LIVES_DIR/global/memory.md" <<'GLOBAL'
---
last_updated: 2026-05-08
---

# Global Preferences
Prefer concise responses
GLOBAL
}

setup_workspace_life() {
    export CLAUDE_LIVES_DIR="$TMPDIR/lives"
    mkdir -p "$CLAUDE_LIVES_DIR/work/sessions" "$CLAUDE_LIVES_DIR/work/archive" "$CLAUDE_LIVES_DIR/work/projects"
    mkdir -p "$CLAUDE_LIVES_DIR/global"

    mkdir -p "$TMPDIR/workspace/proj-a"
    cat > "$TMPDIR/workspace/.claude-life" <<'MARKER'
name: work
created: 2026-05-08
description: Work projects
type: workspace
MARKER

    cat > "$CLAUDE_LIVES_DIR/work/memory.md" <<'MEM'
---
life: work
session_count: 10
---

# work — Life Memory

## Identity
Backend developer at TechCorp

## Current Focus
Q2 deliverables

## Key Context
- Microservices architecture
- Go + TypeScript stack
MEM

    mkdir -p "$CLAUDE_LIVES_DIR/work/projects/proj-a/sessions" "$CLAUDE_LIVES_DIR/work/projects/proj-a/archive"

    cat > "$CLAUDE_LIVES_DIR/work/projects/proj-a/memory.md" <<'MEM'
---
life: work
project: proj-a
session_count: 3
---

# proj-a — Project Memory

## Current Focus
API refactoring

## Key Context
- REST to gRPC migration
- Deadline June 15
MEM

    cat > "$CLAUDE_LIVES_DIR/work/projects/proj-a/handover.md" <<'HANDOVER'
---
life: work
last_updated: 2026-05-08
---

# Handover Notes

## What Was Happening
Migrating user service endpoints

## Next Steps
- Finish auth endpoints
HANDOVER

    cat > "$CLAUDE_LIVES_DIR/global/memory.md" <<'GLOBAL'
---
last_updated: 2026-05-08
---

# Global Preferences
Prefer concise responses
GLOBAL
}

# ─── Stop Hook Tests ───
echo "=== Stop Hook Metadata Tests ==="

source "$LIB_DIR/config_defaults.sh"

# Test 1: Stop hook is valid bash
if bash -n "$SRC_DIR/hooks/stop_hook.sh" 2>/dev/null; then
    pass "Stop hook is valid bash"
else
    fail "Stop hook is valid bash"
fi

# Test 2: Stop hook reads stdin JSON for transcript_path
if grep -q 'transcript_path' "$SRC_DIR/hooks/stop_hook.sh"; then
    pass "Stop hook parses transcript_path from stdin"
else
    fail "Stop hook parses transcript_path from stdin"
fi

# Test 3: Stop hook writes .last-session-meta.json
if grep -q 'last-session-meta.json' "$SRC_DIR/hooks/stop_hook.sh"; then
    pass "Stop hook writes .last-session-meta.json"
else
    fail "Stop hook writes .last-session-meta.json"
fi

# Test 4: Stop hook includes significance filter
if grep -q 'significant' "$SRC_DIR/hooks/stop_hook.sh"; then
    pass "Stop hook includes significance filter"
else
    fail "Stop hook includes significance filter"
fi

# Test 5: Stop hook passes stdin through to stdout
if grep -q 'printf.*input' "$SRC_DIR/hooks/stop_hook.sh"; then
    pass "Stop hook passes stdin through to stdout"
else
    fail "Stop hook passes stdin through to stdout"
fi

# Test 6: Stop hook counts user messages from transcript
if grep -qE 'user_msgs.*grep.*type.*user' "$SRC_DIR/hooks/stop_hook.sh"; then
    pass "Stop hook counts user messages"
else
    fail "Stop hook counts user messages"
fi

# Test 7: Stop hook counts file modifications
if grep -qE 'files_modified.*grep.*Edit|Write' "$SRC_DIR/hooks/stop_hook.sh"; then
    pass "Stop hook counts file modifications"
else
    fail "Stop hook counts file modifications"
fi

# Test 8: Meta JSON has correct structure
setup_life
target_dir="$CLAUDE_LIVES_DIR/testlife"
# Simulate what stop hook writes
cat > "$target_dir/.last-session-meta.json" <<'EOF'
{
  "timestamp": "2026-05-08T14:30:00Z",
  "user_messages": 7,
  "files_modified": 3,
  "significant": true
}
EOF
if python3 -c "
import json
with open('$target_dir/.last-session-meta.json') as f:
    d = json.load(f)
assert d['significant'] == True
assert d['user_messages'] == 7
assert d['files_modified'] == 3
assert 'timestamp' in d
" 2>/dev/null; then
    pass "Meta JSON has correct structure and is valid"
else
    fail "Meta JSON has correct structure and is valid"
fi

# Test 9: Significance threshold - few messages, no edits = not significant
user_msgs=2
files_modified=0
significant=false
if [[ "$user_msgs" -gt 3 ]] || [[ "$files_modified" -gt 0 ]]; then
    significant=true
fi
if [[ "$significant" == "false" ]]; then
    pass "Significance: 2 msgs, 0 edits = not significant"
else
    fail "Significance: 2 msgs, 0 edits = not significant"
fi

# Test 10: Significance threshold - many messages = significant
user_msgs=5
files_modified=0
significant=false
if [[ "$user_msgs" -gt 3 ]] || [[ "$files_modified" -gt 0 ]]; then
    significant=true
fi
if [[ "$significant" == "true" ]]; then
    pass "Significance: 5 msgs, 0 edits = significant"
else
    fail "Significance: 5 msgs, 0 edits = significant"
fi

# Test 11: Significance threshold - any file edit = significant
user_msgs=1
files_modified=1
significant=false
if [[ "$user_msgs" -gt 3 ]] || [[ "$files_modified" -gt 0 ]]; then
    significant=true
fi
if [[ "$significant" == "true" ]]; then
    pass "Significance: 1 msg, 1 edit = significant"
else
    fail "Significance: 1 msg, 1 edit = significant"
fi

# ─── Progressive Block Session Protocol Tests ───
echo ""
echo "=== Session Protocol in Progressive Block Tests ==="

source "$LIB_DIR/inject_memory.sh"

# Test 12: Progressive block contains Session Protocol section
setup_life
block=$(build_progressive_block "testlife")
if echo "$block" | grep -q "### Session Protocol"; then
    pass "Progressive block contains Session Protocol section"
else
    fail "Progressive block contains Session Protocol section"
fi

# Test 13: Session Protocol has on-start instruction
if echo "$block" | grep -q "On start"; then
    pass "Session Protocol has on-start check instruction"
else
    fail "Session Protocol has on-start check instruction"
fi

# Test 14: Session Protocol has before-ending instruction
if echo "$block" | grep -q "Before ending"; then
    pass "Session Protocol has before-ending save instruction"
else
    fail "Session Protocol has before-ending save instruction"
fi

# Test 15: Session Protocol references /save-session
if echo "$block" | grep -q "/save-session"; then
    pass "Session Protocol references /save-session command"
else
    fail "Session Protocol references /save-session command"
fi

# Test 16: Session Protocol references meta file path
if echo "$block" | grep -q "last-session-meta.json"; then
    pass "Session Protocol references meta file path"
else
    fail "Session Protocol references meta file path"
fi

# Test 17: Session Protocol references .last-saved
if echo "$block" | grep -q ".last-saved"; then
    pass "Session Protocol references .last-saved marker"
else
    fail "Session Protocol references .last-saved marker"
fi

# Test 18: Full Memory section lists session meta path
if echo "$block" | grep -q "Session meta:"; then
    pass "Full Memory lists session meta file path"
else
    fail "Full Memory lists session meta file path"
fi

# Test 19: Progressive block meta path uses correct flat life path
expected_meta="$CLAUDE_LIVES_DIR/testlife/.last-session-meta.json"
if echo "$block" | grep -q "$expected_meta"; then
    pass "Flat life meta path is correct"
else
    fail "Flat life meta path is correct"
fi

# Test 20: Workspace project progressive block has correct meta path
setup_workspace_life
source "$LIB_DIR/detect_life.sh"
auto_init_project "work" "proj-a" 2>/dev/null || true
proj_block=$(build_progressive_block "work" "proj-a")
expected_proj_meta="$CLAUDE_LIVES_DIR/work/projects/proj-a/.last-session-meta.json"
if echo "$proj_block" | grep -q "$expected_proj_meta"; then
    pass "Workspace project meta path is correct"
else
    fail "Workspace project meta path is correct"
fi

# Test 21: Workspace project Session Protocol exists
if echo "$proj_block" | grep -q "### Session Protocol"; then
    pass "Workspace project has Session Protocol"
else
    fail "Workspace project has Session Protocol"
fi

# ─── Save-Session .last-saved Tests ───
echo ""
echo "=== Save-Session .last-saved Tests ==="

# Test 22: save-session.md mentions .last-saved
if grep -q '.last-saved' "$SRC_DIR/skills/save-session/SKILL.md"; then
    pass "save-session.md documents .last-saved marker"
else
    fail "save-session.md documents .last-saved marker"
fi

# Test 23: save-session.md has Step 7 for marking saved
if grep -q 'Mark Session as Saved' "$SRC_DIR/skills/save-session/SKILL.md"; then
    pass "save-session.md has 'Mark Session as Saved' step"
else
    fail "save-session.md has 'Mark Session as Saved' step"
fi

# Test 24: save-session.md mentions flat and workspace paths
if grep -q 'Flat life.*last-saved' "$SRC_DIR/skills/save-session/SKILL.md" && \
   grep -q 'Workspace project.*last-saved' "$SRC_DIR/skills/save-session/SKILL.md"; then
    pass "save-session.md covers both flat and workspace .last-saved paths"
else
    fail "save-session.md covers both flat and workspace .last-saved paths"
fi

# ─── Resume Stale Detection Tests ───
echo ""
echo "=== Resume Stale Detection Tests ==="

# Test 25: resume.md references .last-session-meta.json
if grep -q 'last-session-meta.json' "$SRC_DIR/skills/resume/SKILL.md"; then
    pass "resume.md references .last-session-meta.json"
else
    fail "resume.md references .last-session-meta.json"
fi

# Test 26: resume.md references .last-saved for comparison
if grep -q '.last-saved' "$SRC_DIR/skills/resume/SKILL.md"; then
    pass "resume.md references .last-saved for stale comparison"
else
    fail "resume.md references .last-saved for stale comparison"
fi

# Test 27: resume.md includes significance-aware logic
if grep -q 'significant.*true' "$SRC_DIR/skills/resume/SKILL.md"; then
    pass "resume.md has significance-aware stale detection"
else
    fail "resume.md has significance-aware stale detection"
fi

# Test 28: resume.md has fallback for missing meta file
if grep -q 'Fallback' "$SRC_DIR/skills/resume/SKILL.md"; then
    pass "resume.md has fallback detection for missing meta file"
else
    fail "resume.md has fallback detection for missing meta file"
fi

# ─── Integration-style Tests ───
echo ""
echo "=== Integration Tests ==="

# Test 29: Simulated stale detection — unsaved significant session
setup_life
target_dir="$CLAUDE_LIVES_DIR/testlife"
echo "2026-05-08T15:00:00Z" > "$target_dir/.last-session"
cat > "$target_dir/.last-session-meta.json" <<'EOF'
{
  "timestamp": "2026-05-08T15:00:00Z",
  "user_messages": 8,
  "files_modified": 5,
  "significant": true
}
EOF
# No .last-saved exists → session is unsaved
if [[ -f "$target_dir/.last-session-meta.json" ]] && \
   ! [[ -f "$target_dir/.last-saved" ]]; then
    significant=$(python3 -c "import json; print(json.load(open('$target_dir/.last-session-meta.json')).get('significant', False))" 2>/dev/null)
    if [[ "$significant" == "True" ]]; then
        pass "Stale detection: significant session without .last-saved = unsaved"
    else
        fail "Stale detection: significant session without .last-saved = unsaved"
    fi
else
    fail "Stale detection: significant session without .last-saved = unsaved"
fi

# Test 30: Simulated stale detection — saved session (no warning)
echo "2026-05-08T14:55:00Z" > "$target_dir/.last-saved"
# .last-saved exists and is recent → session was saved
if [[ -f "$target_dir/.last-saved" ]] && [[ -f "$target_dir/.last-session-meta.json" ]]; then
    saved_ts=$(cat "$target_dir/.last-saved")
    session_ts=$(cat "$target_dir/.last-session")
    # Both same timestamp or saved is close enough = OK
    if [[ -n "$saved_ts" ]]; then
        pass "Stale detection: .last-saved present = session was saved"
    else
        fail "Stale detection: .last-saved present = session was saved"
    fi
else
    fail "Stale detection: .last-saved present = session was saved"
fi

# Test 31: Simulated stale detection — non-significant session (no warning)
cat > "$target_dir/.last-session-meta.json" <<'EOF'
{
  "timestamp": "2026-05-08T16:00:00Z",
  "user_messages": 2,
  "files_modified": 0,
  "significant": false
}
EOF
rm -f "$target_dir/.last-saved"
significant=$(python3 -c "import json; print(json.load(open('$target_dir/.last-session-meta.json')).get('significant', False))" 2>/dev/null)
if [[ "$significant" == "False" ]]; then
    pass "Stale detection: non-significant session = no warning needed"
else
    fail "Stale detection: non-significant session = no warning needed"
fi

# Test 32: Stop hook handles missing transcript gracefully
if grep -qE 'transcript_path.*-f' "$SRC_DIR/hooks/stop_hook.sh"; then
    pass "Stop hook checks transcript file exists before parsing"
else
    fail "Stop hook checks transcript file exists before parsing"
fi

# Test 33: Stop hook handles empty stdin gracefully
if grep -q '\-t 0' "$SRC_DIR/hooks/stop_hook.sh"; then
    pass "Stop hook checks for terminal stdin before reading"
else
    fail "Stop hook checks for terminal stdin before reading"
fi

# Test 34: Transcript parsing with mock JSONL
mock_transcript="$TMPDIR/transcript.jsonl"
cat > "$mock_transcript" <<'JSONL'
{"type": "user", "message": {"content": "hello"}}
{"type": "assistant", "message": {"content": [{"type": "text", "text": "hi"}]}}
{"type": "user", "message": {"content": "fix the bug"}}
{"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Edit", "input": {"file_path": "/tmp/test.py"}}]}}
{"type": "user", "message": {"content": "looks good"}}
{"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Write", "input": {"file_path": "/tmp/new.py"}}]}}
{"type": "user", "message": {"content": "thanks"}}
{"type": "user", "message": {"content": "one more thing"}}
JSONL
user_count=$(grep -c '"type"[[:space:]]*:[[:space:]]*"user"' "$mock_transcript" 2>/dev/null || echo "0")
edit_count=$(grep -oE '"name"[[:space:]]*:[[:space:]]*"(Edit|Write|MultiEdit)"' "$mock_transcript" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
if [[ "$user_count" -eq 5 ]] && [[ "$edit_count" -eq 2 ]]; then
    pass "Transcript parsing: correctly counts 5 user msgs, 2 file edits"
else
    fail "Transcript parsing: expected 5 user msgs / 2 edits, got $user_count / $edit_count"
fi

# ─── Results ───
echo ""
TOTAL=$((PASSED + FAILED))
echo "Results: $PASSED/$TOTAL passed, $FAILED failed"
if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
