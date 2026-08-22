#!/bin/bash
# Runner for the suites in scripts/tests/.
#
# Tests run without sudo or network by mocking environments.
# Usage: bash scripts/test_programs.sh [name ...]
#
# With no arguments, runs every scripts/tests/test_*.sh. With arguments, runs
# only the named suites -- `bash scripts/test_programs.sh wezterm terminator`
# -- which is the point of the split: touching one program script no longer
# means waiting on every other program's tests.
#
# Each suite is also directly executable on its own:
#   bash scripts/tests/test_wezterm.sh

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$DOTFILES_DIR/scripts/tests"

if [ $# -gt 0 ]; then
    SUITES=()
    for name in "$@"; do
        # accept "wezterm", "test_wezterm", or "test_wezterm.sh"
        candidate="$TESTS_DIR/test_${name#test_}"
        candidate="${candidate%.sh}.sh"
        if [ -f "$candidate" ]; then
            SUITES+=("$candidate")
        else
            echo "No such suite: $name (looked for $candidate)" >&2
            exit 1
        fi
    done
else
    mapfile -t SUITES < <(find "$TESTS_DIR" -maxdepth 1 -name 'test_*.sh' | sort)
fi

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=()
RESULT_FILE="$(mktemp)"
trap 'rm -f "$RESULT_FILE"' EXIT

for suite in "${SUITES[@]}"; do
    name="$(basename "$suite" .sh)"
    : > "$RESULT_FILE"
    # Each suite runs in its own process, so one blowing up cannot take the
    # rest of the run with it, and its mktemp fixture is cleaned by its own trap.
    TEST_RESULT_FILE="$RESULT_FILE" bash "$suite"
    suite_code=$?
    # finish_suite writes "<pass> <fail>"; a suite that died before reaching it
    # leaves the file empty, which must count as a failure rather than a zero.
    if read -r p f < "$RESULT_FILE" && [ -n "${p:-}" ]; then
        TOTAL_PASS=$((TOTAL_PASS + p))
        TOTAL_FAIL=$((TOTAL_FAIL + f))
        [ "$f" -gt 0 ] && FAILED_SUITES+=("$name")
    else
        echo "  ERROR: $name exited $suite_code without reporting results"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
        FAILED_SUITES+=("$name (crashed)")
    fi
done

echo ""
echo "=========================================="
echo "  Test Results: $TOTAL_PASS passed, $TOTAL_FAIL failed"
if [ ${#FAILED_SUITES[@]} -gt 0 ]; then
    echo "  Failing suites: ${FAILED_SUITES[*]}"
fi
echo "=========================================="

[ "$TOTAL_FAIL" -eq 0 ]
