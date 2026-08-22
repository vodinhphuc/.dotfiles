#!/bin/bash
# Shared assertions for the suites in scripts/tests/.
#
# Sourced, never executed. Every helper bumps PASS or FAIL, and finish_suite
# reports them -- both readably and, when TEST_RESULT_FILE is set,
# machine-readably, so the runner never has to scrape human output to total up.
#
# These used to live inline in scripts/test_programs.sh, where the file had
# grown long enough that assert_file_contains was once defined twice with
# different argument orders -- the shadowed copy sat there as dead code until a
# caller used the wrong order and got a baffling failure. One definition in one
# place is the point of this file.

PASS=0
FAIL=0

assert_exit_zero() {
    local desc="$1" code="$2"
    if [ "$code" -eq 0 ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (exit code: $code)"
        FAIL=$((FAIL + 1))
    fi
}

assert_output_contains() {
    local desc="$1" expected="$2" actual="$3"
    if echo "$actual" | grep -q "$expected"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        expected output to contain: '$expected'"
        echo "        actual: '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_output_not_contains() {
    local desc="$1" expected="$2" actual="$3"
    if ! echo "$actual" | grep -q "$expected"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        output should NOT contain: '$expected'"
        echo "        actual: '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local desc="$1" file="$2"
    if [ -f "$file" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (file not found: $file)"
        FAIL=$((FAIL + 1))
    fi
}

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

# `--` before the needle lets callers grep for something starting with a dash.
assert_file_contains() {
    local desc="$1" file="$2"
    shift 2
    [ "${1:-}" = "--" ] && shift
    local needle="$1"
    if [ -f "$file" ] && grep -qF -- "$needle" "$file"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        file:   $file"
        echo "        needle: '$needle'"
        FAIL=$((FAIL + 1))
    fi
}

assert_dir_exists() {
    local desc="$1" dir="$2"
    if [ -d "$dir" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (directory not found: $dir)"
        FAIL=$((FAIL + 1))
    fi
}

# Print this suite's tally, and hand the raw numbers to the runner when it asks
# for them. Exits non-zero if anything failed, so a suite run on its own is
# still usable from a pipeline or a git hook.
finish_suite() {
    local name="${1:-suite}"
    echo ""
    echo "  $name: $PASS passed, $FAIL failed"
    if [ -n "${TEST_RESULT_FILE:-}" ]; then
        echo "$PASS $FAIL" > "$TEST_RESULT_FILE"
    fi
    [ "$FAIL" -eq 0 ]
}
