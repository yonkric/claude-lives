#!/usr/bin/env bash
# Don't use set -e since we test error cases

# Unit tests for token_count.sh
# Tests both tiktoken (if available) and heuristic fallback

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../../lib" && pwd)"
TOKEN_COUNT="$LIB_DIR/token_count.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
pass() {
    echo "  ✓ PASS: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo "  ✗ FAIL: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test $TESTS_RUN: $1"
}

# Setup temp directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "================================"
echo "Token Count Unit Tests"
echo "================================"
echo ""

# Test 1: Check tokenizer info
run_test "Token counter returns info"
if $TOKEN_COUNT --info | grep -q "Tokenizer:"; then
    pass "Tokenizer info displayed"
else
    fail "Tokenizer info not displayed"
fi

# Test 2: Count simple string
run_test "Count tokens in simple string"
result=$($TOKEN_COUNT --string "hello world")
if [[ "$result" =~ ^[0-9]+$ && "$result" -gt 0 ]]; then
    pass "String token count: $result"
else
    fail "Invalid token count: $result"
fi

# Test 3: Count longer text
run_test "Count tokens in longer text"
text="This is a longer test string with multiple words to verify token counting accuracy."
result=$($TOKEN_COUNT --string "$text")
if [[ "$result" =~ ^[0-9]+$ && "$result" -gt 5 ]]; then
    pass "Long text token count: $result"
else
    fail "Invalid token count for long text: $result"
fi

# Test 4: Count empty string
run_test "Count tokens in empty string"
result=$($TOKEN_COUNT --string "")
if [[ "$result" == "0" ]]; then
    pass "Empty string returns 0"
else
    fail "Empty string should return 0, got: $result"
fi

# Test 5: Count non-existent file
run_test "Count tokens in non-existent file"
result=$($TOKEN_COUNT "$TEMP_DIR/nonexistent.txt")
if [[ "$result" == "0" ]]; then
    pass "Non-existent file returns 0"
else
    fail "Non-existent file should return 0, got: $result"
fi

# Test 6: Count existing file
run_test "Count tokens in existing file"
echo "This is test content for token counting." > "$TEMP_DIR/test.txt"
result=$($TOKEN_COUNT "$TEMP_DIR/test.txt")
if [[ "$result" =~ ^[0-9]+$ && "$result" -gt 0 ]]; then
    pass "File token count: $result"
else
    fail "Invalid token count for file: $result"
fi

# Test 7: Count empty file
run_test "Count tokens in empty file"
touch "$TEMP_DIR/empty.txt"
result=$($TOKEN_COUNT "$TEMP_DIR/empty.txt")
if [[ "$result" == "0" ]]; then
    pass "Empty file returns 0"
else
    fail "Empty file should return 0, got: $result"
fi

# Test 8: Unicode content handling
run_test "Count tokens with unicode content"
echo "日本語のテスト 中文测试 🎉 émojis" > "$TEMP_DIR/unicode.txt"
result=$($TOKEN_COUNT "$TEMP_DIR/unicode.txt")
if [[ "$result" =~ ^[0-9]+$ && "$result" -gt 3 ]]; then
    pass "Unicode content token count: $result"
else
    fail "Unicode handling failed: $result"
fi

# Test 9: Count directory
run_test "Count tokens in directory"
mkdir -p "$TEMP_DIR/subdir"
echo "File one" > "$TEMP_DIR/subdir/file1.md"
echo "File two with more content" > "$TEMP_DIR/subdir/file2.md"
result=$($TOKEN_COUNT --dir "$TEMP_DIR/subdir")
if [[ "$result" =~ ^[0-9]+$ && "$result" -gt 5 ]]; then
    pass "Directory token count: $result"
else
    fail "Invalid directory token count: $result"
fi

# Test 10: Count empty directory
run_test "Count tokens in empty directory"
mkdir -p "$TEMP_DIR/emptydir"
result=$($TOKEN_COUNT --dir "$TEMP_DIR/emptydir")
if [[ "$result" =~ ^[0-9]+$ && "$result" -eq 0 ]]; then
    pass "Empty directory returns 0"
else
    fail "Empty directory should return 0, got: $result"
fi

# Test 11: Consistency check
run_test "Token count is consistent"
text="Consistent test string for verification"
result1=$($TOKEN_COUNT --string "$text")
result2=$($TOKEN_COUNT --string "$text")
if [[ "$result1" == "$result2" ]]; then
    pass "Consistent results: $result1"
else
    fail "Inconsistent: $result1 vs $result2"
fi

# Test 12: Large content
run_test "Handle large content"
python3 -c "print('word ' * 1000)" > "$TEMP_DIR/large.txt"
result=$($TOKEN_COUNT "$TEMP_DIR/large.txt")
if [[ "$result" =~ ^[0-9]+$ && "$result" -gt 100 ]]; then
    pass "Large content handled: $result tokens"
else
    fail "Large content failed: $result"
fi

# Test 13: Special characters
run_test "Handle special characters"
echo 'Special: <>&"'"'"'$%^&*()' > "$TEMP_DIR/special.txt"
result=$($TOKEN_COUNT "$TEMP_DIR/special.txt")
if [[ "$result" =~ ^[0-9]+$ && "$result" -gt 0 ]]; then
    pass "Special chars handled: $result"
else
    fail "Special chars failed: $result"
fi

# Summary
echo ""
echo "================================"
echo "Test Summary"
echo "================================"
echo "Total:  $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
