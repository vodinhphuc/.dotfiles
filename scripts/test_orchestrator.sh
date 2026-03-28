#!/bin/bash
# Tests for run_step orchestrator function in install.sh
# Usage: bash scripts/test_orchestrator.sh

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

# --- Test helpers ---

assert_equals() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        expected: '$expected'"
        echo "        actual:   '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_contains() {
    local desc="$1" file="$2" content="$3"
    if grep -qx "$content" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        expected '$content' in $file"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_not_contains() {
    local desc="$1" file="$2" content="$3"
    if ! grep -qx "$content" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        expected '$content' NOT in $file"
        FAIL=$((FAIL + 1))
    fi
}

# --- Setup: override state file paths and source functions ---

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

export STATE_FILE="$TEST_DIR/.install_state"
export ERRORS_FILE="$TEST_DIR/.install_errors"
export LOG_FILE="$TEST_DIR/.install.log"
touch "$ERRORS_FILE"

# Source only the functions (not main body) from install.sh
# Then disable set -e so test assertions can handle failures gracefully
source "$DOTFILES_DIR/scripts/install.sh"
set +e

# --- Tests ---

echo ""
echo "=== Test: successful step is recorded in state file ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_ok" <(echo "exit 0")
assert_file_contains "state file contains test_ok" "$STATE_FILE" "test_ok"
assert_file_not_contains "errors file does not contain test_ok" "$ERRORS_FILE" "test_ok"
assert_equals "STEPS_OK has test_ok" "test_ok" "${STEPS_OK[0]:-}"

echo ""
echo "=== Test: already-completed step is skipped ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_ok" <(echo "exit 0")
assert_equals "STEPS_SKIP has test_ok" "test_ok" "${STEPS_SKIP[0]:-}"
assert_equals "STEPS_OK is empty" "" "${STEPS_OK[0]:-}"

echo ""
echo "=== Test: failing step is recorded in errors file ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_fail" <(echo "exit 1")
assert_file_contains "errors file contains test_fail" "$ERRORS_FILE" "test_fail"
assert_file_not_contains "state file does not contain test_fail" "$STATE_FILE" "test_fail"
assert_equals "STEPS_FAIL has test_fail" "test_fail" "${STEPS_FAIL[0]:-}"

echo ""
echo "=== Test: failure in one step does not abort subsequent steps ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_abort_check" <(echo "exit 0")
assert_file_contains "state file contains test_abort_check after prior failure" "$STATE_FILE" "test_abort_check"

echo ""
echo "=== Test: exit inside script does not kill orchestrator ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_exit_trap" <(printf '#!/bin/bash\nexit 42')
assert_equals "orchestrator still running after exit 42" "test_exit_trap" "${STEPS_FAIL[0]:-}"

# --- Summary ---
echo ""
echo "=========================================="
echo "  Test Results: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ] || exit 1
