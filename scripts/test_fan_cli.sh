#!/bin/bash
# Unit tests for .local/bin/fan against a fake hwmon tree.
# Sourced shared assertions from test_programs.sh would couple the files;
# keep this file standalone so it can also be run directly.
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAN="$DOTFILES_DIR/.local/bin/fan"
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

assert_exit_nonzero() {
    local desc="$1" code="$2"
    if [ "$code" -ne 0 ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (exit code was 0)"
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
        echo "        expected: '$expected'"
        echo "        actual: '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_contents() {
    local desc="$1" file="$2" expected="$3"
    if [ -f "$file" ] && [ "$(cat "$file")" = "$expected" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        file: $file"
        echo "        expected: '$expected'"
        echo "        actual: '$(cat "$file" 2>/dev/null || echo '<missing>')'"
        FAIL=$((FAIL + 1))
    fi
}

# --- fixture: build a fake hwmon tree ---
HW="$(mktemp -d)"
trap 'rm -rf "$HW"' EXIT

# hwmon0: nct6798 — controllable, has fan/temp/pwm
mkdir -p "$HW/hwmon0"
echo nct6798 > "$HW/hwmon0/name"
echo 1200    > "$HW/hwmon0/fan1_input"
echo CPU_FAN > "$HW/hwmon0/fan1_label"
echo 128     > "$HW/hwmon0/pwm1"
echo 2       > "$HW/hwmon0/pwm1_enable"
echo 42000   > "$HW/hwmon0/temp1_input"
echo CPU     > "$HW/hwmon0/temp1_label"

# hwmon1: nvme — must be skipped (no pwm)
mkdir -p "$HW/hwmon1"
echo nvme    > "$HW/hwmon1/name"
echo 38000   > "$HW/hwmon1/temp1_input"

# hwmon2: coretemp — must be skipped
mkdir -p "$HW/hwmon2"
echo coretemp > "$HW/hwmon2/name"
echo 45000    > "$HW/hwmon2/temp1_input"

run_fan() { HWMON_ROOT="$HW" FAN_DRY_RUN=1 "$FAN" "$@" 2>&1; }

# --- help ---
echo ""
echo "=== fan: help / no args ==="
output=$(run_fan -h); code=$?
assert_exit_zero "fan -h exits 0" "$code"
assert_output_contains "fan -h shows usage" "Usage: fan" "$output"

# --- list ---
echo ""
echo "=== fan list ==="
output=$(run_fan list); code=$?
assert_exit_zero "fan list exits 0" "$code"
assert_output_contains "fan list shows pwm1 from nct6798" "pwm1" "$output"
assert_output_contains "fan list shows label" "CPU_FAN" "$output"
# Negative: must not list nvme/coretemp (no pwm there)

# --- status ---
echo ""
echo "=== fan status ==="
output=$(run_fan status); code=$?
assert_exit_zero "fan status exits 0" "$code"
assert_output_contains "fan status shows fan RPM" "1200" "$output"
assert_output_contains "fan status shows temp in C" "42" "$output"
assert_output_contains "fan status shows PWM percent" "50%" "$output"
assert_output_contains "fan status shows mode label" "auto" "$output"

# --- set: validation ---
echo ""
echo "=== fan set: validation ==="
output=$(run_fan set pwm1 101); code=$?
assert_exit_nonzero "fan set rejects >100" "$code"
output=$(run_fan set pwm1 -1); code=$?
assert_exit_nonzero "fan set rejects negative" "$code"
output=$(run_fan set pwm1 abc); code=$?
assert_exit_nonzero "fan set rejects non-integer" "$code"
output=$(run_fan set pwm1 0); code=$?
assert_exit_nonzero "fan set rejects 0 without --force" "$code"
output=$(run_fan set pwm9 50); code=$?
assert_exit_nonzero "fan set rejects unknown channel" "$code"
assert_output_contains "fan set unknown-channel error lists pwm1" "pwm1" "$output"

# --- set: writes ---
echo ""
echo "=== fan set: writes pwm and pwm_enable ==="
output=$(run_fan set pwm1 60); code=$?
assert_exit_zero "fan set pwm1 60 exits 0" "$code"
assert_file_contents "pwm1_enable was set to 1 (manual)" "$HW/hwmon0/pwm1_enable" "1"
assert_file_contents "pwm1 was set to 153 (60% of 255)" "$HW/hwmon0/pwm1" "153"

# --force allows zero
echo 2 > "$HW/hwmon0/pwm1_enable"  # reset
echo 128 > "$HW/hwmon0/pwm1"
output=$(run_fan set pwm1 0 --force); code=$?
assert_exit_zero "fan set pwm1 0 --force exits 0" "$code"
assert_file_contents "pwm1 was set to 0 with --force" "$HW/hwmon0/pwm1" "0"

# --- manual / auto: dry-run prints systemctl invocation ---
echo ""
echo "=== fan manual / auto (dry run) ==="
output=$(run_fan manual); code=$?
assert_exit_zero "fan manual exits 0 (dry run)" "$code"
assert_output_contains "fan manual would stop fancontrol" "systemctl stop fancontrol" "$output"
output=$(run_fan auto); code=$?
assert_exit_zero "fan auto exits 0 (dry run)" "$code"
assert_output_contains "fan auto would start fancontrol" "systemctl start fancontrol" "$output"

# --- empty hwmon tree: status fails clearly ---
echo ""
echo "=== fan status: no controllable fans ==="
EMPTY="$(mktemp -d)"
trap 'rm -rf "$HW" "$EMPTY"' EXIT
output=$(HWMON_ROOT="$EMPTY" FAN_DRY_RUN=1 "$FAN" status 2>&1); code=$?
assert_exit_nonzero "fan status exits non-zero on empty tree" "$code"
assert_output_contains "fan status references the guide" "docs/guides/fans.md" "$output"

# --- summary ---
echo ""
echo "=========================================="
echo "  fan CLI: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ] || exit 1
