#!/bin/bash
# Unit tests for .local/bin/rgb against a fake openrgb binary.
# Standalone (like test_fan_cli.sh) so it can be run directly.
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RGB="$DOTFILES_DIR/.local/bin/rgb"
PASS=0
FAIL=0

assert_exit_zero() {
    local desc="$1" code="$2"
    if [ "$code" -eq 0 ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (exit code: $code)"; FAIL=$((FAIL + 1))
    fi
}

assert_exit_nonzero() {
    local desc="$1" code="$2"
    if [ "$code" -ne 0 ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (exit code was 0)"; FAIL=$((FAIL + 1))
    fi
}

assert_output_contains() {
    local desc="$1" expected="$2" actual="$3"
    if echo "$actual" | grep -qF "$expected"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        expected: '$expected'"
        echo "        actual: '$actual'"
        FAIL=$((FAIL + 1))
    fi
}

# --- fixture: a fake openrgb that answers --list-devices ---
BIN="$(mktemp -d)"
trap 'rm -rf "$BIN"' EXIT
FAKE="$BIN/openrgb"
cat > "$FAKE" <<'EOF'
#!/bin/bash
for a in "$@"; do
    if [ "$a" = "--list-devices" ]; then
        cat <<'DEV'
0: ASUS Aura Motherboard
  Type: Motherboard
1: G.SKILL Trident Z5 RGB
  Type: DRAM
2: Corsair Vengeance RGB RAM
  Type: DRAM
DEV
        exit 0
    fi
done
exit 0
EOF
chmod +x "$FAKE"

run_rgb() { OPENRGB_BIN="$FAKE" RGB_DRY_RUN=1 RGB_SUDO= "$RGB" "$@" 2>&1; }

# --- help ---
echo ""
echo "=== rgb: help / no args ==="
output=$(run_rgb -h); code=$?
assert_exit_zero "rgb -h exits 0" "$code"
assert_output_contains "rgb -h shows usage" "Usage: rgb" "$output"

# --- list ---
echo ""
echo "=== rgb list ==="
output=$(run_rgb list); code=$?
assert_exit_zero "rgb list exits 0" "$code"
assert_output_contains "rgb list shows device 0 (Aura)" "0: ASUS Aura" "$output"
assert_output_contains "rgb list shows RAM device" "Corsair Vengeance RGB RAM" "$output"

# --- colors ---
echo ""
echo "=== rgb colors ==="
output=$(run_rgb colors); code=$?
assert_exit_zero "rgb colors exits 0" "$code"
assert_output_contains "rgb colors lists 'magenta'" "magenta" "$output"

# --- off: all vs targeted ---
echo ""
echo "=== rgb off ==="
output=$(run_rgb off); code=$?
assert_exit_zero "rgb off (all) exits 0" "$code"
assert_output_contains "rgb off all = static black, no --device" "openrgb --mode static --color 000000" "$output"
output=$(run_rgb off aura); code=$?
assert_exit_zero "rgb off aura exits 0" "$code"
assert_output_contains "rgb off aura targets --device 0" "openrgb --device 0 --mode static --color 000000" "$output"

# --- on: default, named color, hex, index, name substring ---
echo ""
echo "=== rgb on ==="
output=$(run_rgb on); code=$?
assert_exit_zero "rgb on (all) exits 0" "$code"
assert_output_contains "rgb on all defaults to white" "openrgb --mode static --color FFFFFF" "$output"
output=$(run_rgb on red); code=$?
assert_output_contains "rgb on red (single color arg -> all)" "openrgb --mode static --color FF0000" "$output"
output=$(run_rgb on ram blue); code=$?
assert_output_contains "rgb on ram blue targets device 2" "openrgb --device 2 --mode static --color 0000FF" "$output"
output=$(run_rgb on 0 1e90ff); code=$?
assert_output_contains "rgb on 0 hex uppercases to 1E90FF" "openrgb --device 0 --mode static --color 1E90FF" "$output"
output=$(run_rgb on 0 "#00ff00"); code=$?
assert_output_contains "rgb on strips '#' from hex" "openrgb --device 0 --mode static --color 00FF00" "$output"

# --- on: bad color ---
output=$(run_rgb on 0 notacolor); code=$?
assert_exit_nonzero "rgb on rejects unknown color" "$code"
assert_output_contains "rgb bad-color error points at 'rgb colors'" "rgb colors" "$output"

# --- target resolution errors ---
echo ""
echo "=== rgb target errors ==="
output=$(run_rgb off nope); code=$?
assert_exit_nonzero "rgb off unknown target fails" "$code"
assert_output_contains "unknown target lists available devices" "ASUS Aura" "$output"
output=$(run_rgb off rgb); code=$?
assert_exit_nonzero "rgb ambiguous target fails" "$code"
assert_output_contains "ambiguous target reports multiple matches" "matches multiple" "$output"
output=$(run_rgb off 9); code=$?
assert_exit_nonzero "rgb off bad index fails" "$code"

# --- mode ---
echo ""
echo "=== rgb mode ==="
output=$(run_rgb mode rainbow); code=$?
assert_exit_zero "rgb mode rainbow exits 0" "$code"
assert_output_contains "rgb mode rainbow (all)" "openrgb --mode rainbow" "$output"
output=$(run_rgb mode); code=$?
assert_exit_nonzero "rgb mode with no arg fails" "$code"

# --- persist ---
echo ""
echo "=== rgb persist ==="
output=$(run_rgb persist on); code=$?
assert_exit_zero "rgb persist on exits 0" "$code"
assert_output_contains "rgb persist on enables service" "systemctl enable --now openrgb-off.service" "$output"
output=$(run_rgb persist off); code=$?
assert_exit_zero "rgb persist off exits 0" "$code"
assert_output_contains "rgb persist off disables service" "systemctl disable --now openrgb-off.service" "$output"
output=$(run_rgb persist bogus); code=$?
assert_exit_nonzero "rgb persist with bad arg fails" "$code"

# --- summary ---
echo ""
echo "=========================================="
echo "  rgb CLI: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ] || exit 1
