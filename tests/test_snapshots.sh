#!/usr/bin/env bash
set -euo pipefail

# Tests for the session snapshot system.
# Validates: snapshot.sh library, post_tool_hook.sh, stop_hook integration.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
SRC_DIR="$PROJECT_DIR"
LIB_DIR="$SRC_DIR/lib"

passed=0
failed=0

pass() { echo "  PASS: $1"; passed=$((passed + 1)); }
fail() { echo "  FAIL: $1"; failed=$((failed + 1)); }

# Set up isolated test environment
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

export CLAUDE_LIVES_DIR="$TMPDIR/lives"
mkdir -p "$CLAUDE_LIVES_DIR/global"
mkdir -p "$CLAUDE_LIVES_DIR/testlife/sessions" "$CLAUDE_LIVES_DIR/testlife/archive"

# Create a minimal life
mkdir -p "$TMPDIR/project"
cat > "$TMPDIR/project/.claude-life" <<'EOF'
name: testlife
created: 2026-01-01
description: Test life
type: flat
EOF

cat > "$CLAUDE_LIVES_DIR/testlife/memory.md" <<'EOF'
---
life: testlife
last_compressed: 2026-01-01
session_count: 0
---

# testlife — Life Memory

## Identity
Test life for snapshot testing

## Current Focus
Testing snapshots

## Key Context
- Testing snapshot system
EOF

cat > "$CLAUDE_LIVES_DIR/testlife/config.yaml" <<'EOF'
life_token_budget: 4000
handover_token_budget: 1500
snapshot_tool_threshold: 20
snapshot_max_tokens: 150
snapshot_enabled: true
EOF

# Source the library
source "$LIB_DIR/snapshot.sh"

echo "=== Snapshot Library ==="

# Test 1: snapshot.sh is valid bash
if bash -n "$LIB_DIR/snapshot.sh" 2>/dev/null; then
    pass "snapshot.sh passes syntax check"
else
    fail "snapshot.sh passes syntax check"
fi

# Test 2: get_snapshot_dir returns correct path for flat life
dir=$(get_snapshot_dir "testlife" "")
if [[ "$dir" == "$CLAUDE_LIVES_DIR/testlife/.session-snapshots" ]]; then
    pass "get_snapshot_dir correct for flat life"
else
    fail "get_snapshot_dir correct for flat life (got: $dir)"
fi

# Test 3: get_snapshot_dir returns correct path for workspace project
dir=$(get_snapshot_dir "testlife" "myproject")
if [[ "$dir" == "$CLAUDE_LIVES_DIR/testlife/projects/myproject/.session-snapshots" ]]; then
    pass "get_snapshot_dir correct for workspace project"
else
    fail "get_snapshot_dir correct for workspace project (got: $dir)"
fi

# Test 4: get_snapshot_dir returns correct path for global
dir=$(get_snapshot_dir "" "")
if [[ "$dir" == "$CLAUDE_LIVES_DIR/global/.session-snapshots" ]]; then
    pass "get_snapshot_dir correct for global"
else
    fail "get_snapshot_dir correct for global (got: $dir)"
fi

# Test 5: init_snapshot_session creates directory and files
snap_dir="$TMPDIR/test-snap"
init_snapshot_session "$snap_dir" "testlife" ""
if [[ -d "$snap_dir" && -f "$snap_dir/counter" && -f "$snap_dir/snapshots.md" && -f "$snap_dir/session-id" ]]; then
    pass "init_snapshot_session creates all files"
else
    fail "init_snapshot_session creates all files"
fi

# Test 6: Counter starts at 0
val=$(read_counter "$snap_dir")
if [[ "$val" == "0" ]]; then
    pass "Counter initializes to 0"
else
    fail "Counter initializes to 0 (got: $val)"
fi

# Test 7: increment_counter increments
increment_counter "$snap_dir"
val=$(read_counter "$snap_dir")
if [[ "$val" == "1" ]]; then
    pass "increment_counter increments to 1"
else
    fail "increment_counter increments to 1 (got: $val)"
fi

# Test 8: Multiple increments
increment_counter "$snap_dir"
increment_counter "$snap_dir"
val=$(read_counter "$snap_dir")
if [[ "$val" == "3" ]]; then
    pass "Multiple increments work correctly"
else
    fail "Multiple increments work correctly (got: $val)"
fi

# Test 9: reset_counter resets to 0
reset_counter "$snap_dir"
val=$(read_counter "$snap_dir")
if [[ "$val" == "0" ]]; then
    pass "reset_counter resets to 0"
else
    fail "reset_counter resets to 0 (got: $val)"
fi

# Test 10: snapshot_count with empty file
count=$(snapshot_count "$snap_dir")
if [[ "$count" == "0" ]]; then
    pass "snapshot_count returns 0 for empty file"
else
    fail "snapshot_count returns 0 for empty file (got: $count)"
fi

# Test 11: snapshot_count with snapshots
cat > "$snap_dir/snapshots.md" <<'SNAP'
<!-- snapshot:1 t:2026-05-11T00:00:00Z tools:22 -->
## Snapshot 1
- Did some work

<!-- snapshot:2 t:2026-05-11T01:00:00Z tools:45 -->
## Snapshot 2
- Did more work
SNAP
count=$(snapshot_count "$snap_dir")
if [[ "$count" == "2" ]]; then
    pass "snapshot_count returns 2 for two snapshots"
else
    fail "snapshot_count returns 2 for two snapshots (got: $count)"
fi

# Test 12: read_snapshots returns content
content=$(read_snapshots "$snap_dir")
if echo "$content" | grep -q "Snapshot 1" && echo "$content" | grep -q "Snapshot 2"; then
    pass "read_snapshots returns snapshot content"
else
    fail "read_snapshots returns snapshot content"
fi

# Test 13: cleanup_snapshots removes directory (must be under CLAUDE_LIVES_DIR)
cleanup_snap_dir="$CLAUDE_LIVES_DIR/testlife/.session-snapshots"
mkdir -p "$cleanup_snap_dir"
echo "test" > "$cleanup_snap_dir/counter"
cleanup_snapshots "$cleanup_snap_dir"
if [[ ! -d "$cleanup_snap_dir" ]]; then
    pass "cleanup_snapshots removes directory"
else
    fail "cleanup_snapshots removes directory"
fi

# Test 14: read_cached_life returns cached life name
snap_dir2="$TMPDIR/test-snap-2"
init_snapshot_session "$snap_dir2" "mylife" "myproj"
cached_life=$(read_cached_life "$snap_dir2")
if [[ "$cached_life" == "mylife" ]]; then
    pass "read_cached_life returns cached life"
else
    fail "read_cached_life returns cached life (got: $cached_life)"
fi

# Test 15: read_cached_project returns cached project
cached_proj=$(read_cached_project "$snap_dir2")
if [[ "$cached_proj" == "myproj" ]]; then
    pass "read_cached_project returns cached project"
else
    fail "read_cached_project returns cached project (got: $cached_proj)"
fi
cleanup_snapshots "$snap_dir2"

# Test 16: get_snapshot_threshold reads config
threshold=$(get_snapshot_threshold "testlife")
if [[ "$threshold" == "20" ]]; then
    pass "get_snapshot_threshold reads config value"
else
    fail "get_snapshot_threshold reads config value (got: $threshold)"
fi

# Test 17: get_snapshot_enabled reads config
enabled=$(get_snapshot_enabled "testlife")
if [[ "$enabled" == "true" ]]; then
    pass "get_snapshot_enabled reads config value"
else
    fail "get_snapshot_enabled reads config value (got: $enabled)"
fi

echo ""
echo "=== PostToolUse Hook ==="

# Test 18: post_tool_hook.sh is valid bash
if bash -n "$SRC_DIR/hooks/post_tool_hook.sh" 2>/dev/null; then
    pass "post_tool_hook.sh passes syntax check"
else
    fail "post_tool_hook.sh passes syntax check"
fi

# Test 19: post_tool_hook.sh passes stdin through
hook_output=$(echo '{"tool_name":"Read"}' | bash "$SRC_DIR/hooks/post_tool_hook.sh" 2>/dev/null) || true
if [[ "$hook_output" == '{"tool_name":"Read"}' ]]; then
    pass "post_tool_hook.sh passes stdin through"
else
    fail "post_tool_hook.sh passes stdin through (got: $hook_output)"
fi

# Test 20: Hook performance (should complete in under 200ms)
start_time=$(python3 -c "import time; print(int(time.time()*1000))")
echo '{}' | bash "$SRC_DIR/hooks/post_tool_hook.sh" >/dev/null 2>&1 || true
end_time=$(python3 -c "import time; print(int(time.time()*1000))")
elapsed=$((end_time - start_time))
if [[ "$elapsed" -lt 200 ]]; then
    pass "Hook completes in under 200ms (${elapsed}ms)"
else
    fail "Hook completes in under 200ms (took ${elapsed}ms)"
fi

echo ""
echo "=== Stop Hook Snapshot Preservation ==="

# Test 21: Stop hook writes has_snapshots field
snap_dir3=$(get_snapshot_dir "testlife" "")
init_snapshot_session "$snap_dir3" "testlife" ""
echo "- some snapshot content" > "$snap_dir3/snapshots.md"
# Remove .last-saved so snapshots are "unsaved"
rm -f "$CLAUDE_LIVES_DIR/testlife/.last-saved"

(cd "$TMPDIR/project" && echo '{}' | bash "$SRC_DIR/hooks/stop_hook.sh" >/dev/null 2>&1) || true

meta_file="$CLAUDE_LIVES_DIR/testlife/.last-session-meta.json"
if [[ -f "$meta_file" ]] && grep -q '"has_snapshots"' "$meta_file"; then
    pass "Stop hook writes has_snapshots to meta"
else
    fail "Stop hook writes has_snapshots to meta"
fi

# Test 22: has_snapshots is true when unsaved snapshots exist
if grep -q '"has_snapshots": true' "$meta_file"; then
    pass "has_snapshots is true when unsaved"
else
    fail "has_snapshots is true when unsaved"
fi
cleanup_snapshots "$snap_dir3"

echo ""
echo "=== Installer & Uninstaller ==="

# Test 23: install.sh registers PostToolUse hook
if grep -q "PostToolUse" "$PROJECT_DIR/install.sh" && grep -q "post_tool_hook.sh" "$PROJECT_DIR/install.sh"; then
    pass "install.sh registers PostToolUse hook"
else
    fail "install.sh registers PostToolUse hook"
fi

# Test 24: uninstall.sh removes PostToolUse hook
if grep -q "PostToolUse" "$PROJECT_DIR/uninstall.sh" && grep -q "post_tool_hook.sh" "$PROJECT_DIR/uninstall.sh"; then
    pass "uninstall.sh removes PostToolUse hook"
else
    fail "uninstall.sh removes PostToolUse hook"
fi

# Test 25: checkpoint command exists
if [[ -f "$SRC_DIR/skills/checkpoint/SKILL.md" ]]; then
    pass "checkpoint.md command exists"
else
    fail "checkpoint.md command exists"
fi

# Test 26: checkpoint is in installer command list
if grep -q "checkpoint" "$PROJECT_DIR/install.sh"; then
    pass "checkpoint in installer command list"
else
    fail "checkpoint in installer command list"
fi

echo ""
echo "=== CLAUDE.md Injection ==="

# Test 27: Progressive block includes snapshot protocol
CLAUDE_MD="$TMPDIR/project/CLAUDE.md"
echo "# Test" > "$CLAUDE_MD"
source "$LIB_DIR/inject_memory.sh"
inject_memory "$CLAUDE_MD" "testlife" --progressive
if grep -q "Mid-session snapshots" "$CLAUDE_MD"; then
    pass "Progressive block includes snapshot protocol"
else
    fail "Progressive block includes snapshot protocol"
fi

# Test 28: Progressive block includes counter path
if grep -q "session-snapshots/counter" "$CLAUDE_MD"; then
    pass "Progressive block includes counter path"
else
    fail "Progressive block includes counter path"
fi

echo ""
echo "=== Save-Session Integration ==="

# Test 29: save-session.md includes snapshot merge step
if grep -q "Step 2.5" "$SRC_DIR/skills/save-session/SKILL.md" && grep -q "Session Snapshots" "$SRC_DIR/skills/save-session/SKILL.md"; then
    pass "save-session includes snapshot merge step"
else
    fail "save-session includes snapshot merge step"
fi

# Test 30: save-session.md includes snapshot cleanup step
if grep -q "Step 7.5" "$SRC_DIR/skills/save-session/SKILL.md" && grep -q "Clean Up Snapshots" "$SRC_DIR/skills/save-session/SKILL.md"; then
    pass "save-session includes snapshot cleanup step"
else
    fail "save-session includes snapshot cleanup step"
fi

echo ""
echo "=== Resume Integration ==="

# Test 31: resume.md includes snapshot recovery
if grep -q "preserved snapshots" "$SRC_DIR/skills/resume/SKILL.md" && grep -q "has_snapshots" "$SRC_DIR/skills/resume/SKILL.md"; then
    pass "resume includes snapshot recovery"
else
    fail "resume includes snapshot recovery"
fi

echo ""
echo "=== Configuration ==="

# Test 32: config template includes snapshot settings
if grep -q "snapshot_tool_threshold" "$SRC_DIR/templates/life-config.yaml"; then
    pass "Config template includes snapshot_tool_threshold"
else
    fail "Config template includes snapshot_tool_threshold"
fi

# Test 33: config template includes snapshot_enabled
if grep -q "snapshot_enabled" "$SRC_DIR/templates/life-config.yaml"; then
    pass "Config template includes snapshot_enabled"
else
    fail "Config template includes snapshot_enabled"
fi

# Test 34: config defaults includes snapshot defaults
if grep -q "DEFAULT_SNAPSHOT_TOOL_THRESHOLD" "$LIB_DIR/config_defaults.sh"; then
    pass "Config defaults includes snapshot threshold"
else
    fail "Config defaults includes snapshot threshold"
fi

echo ""
echo "=== is_stale_session ==="

# Test 35: is_stale_session detects stale snapshots
stale_dir="$TMPDIR/stale-snap"
stale_target="$TMPDIR/stale-target"
mkdir -p "$stale_dir" "$stale_target"
cat > "$stale_dir/session-id" <<'EOF'
timestamp: 2026-01-01T00:00:00Z
life: testlife
project:
EOF
echo "2026-05-10T00:00:00Z" > "$stale_target/.last-session"

if is_stale_session "$stale_dir" "$stale_target"; then
    pass "is_stale_session detects stale snapshots"
else
    fail "is_stale_session detects stale snapshots"
fi

# Test 36: is_stale_session returns false for current session
cat > "$stale_dir/session-id" <<'EOF'
timestamp: 2026-05-11T00:00:00Z
life: testlife
project:
EOF
echo "2026-01-01T00:00:00Z" > "$stale_target/.last-session"

if ! is_stale_session "$stale_dir" "$stale_target"; then
    pass "is_stale_session returns false for current session"
else
    fail "is_stale_session returns false for current session"
fi

echo ""
echo "Results: $passed/$((passed + failed)) passed, $failed failed"
