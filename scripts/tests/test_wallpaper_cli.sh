#!/bin/bash
# Unit tests for .local/bin/wallpaper against a fake ImageMagick.
# Standalone (like test_rgb_cli.sh) so it can be run directly.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
WP="$DOTFILES_DIR/.local/bin/wallpaper"

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

assert_equals() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected '$expected', got '$actual')"; FAIL=$((FAIL + 1))
    fi
}

# --- fixture ----------------------------------------------------------------
# A fake `magick`: each "image" is a text file holding "<width> <height>", so
# identify just cats it and a resize rewrites it. That keeps the suite free of
# ImageMagick and of any real binary data.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/magick" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "identify" ]; then
    f="${!#}"; f="${f%\[0\]}"
    cat "$f"
    exit 0
fi
src="$1"; dst="${!#}"; ext=""
while [ $# -gt 0 ]; do
    [ "$1" = "-extent" ] && ext="$2"
    shift
done
[ -f "$src" ] || exit 1
echo "${ext%x*} ${ext#*x}" > "$dst"
EOF
chmod +x "$BIN/magick"

BG="$TMP/bg"
BAK="$TMP/originals"
mkdir -p "$BG"

reset_fixture() {
    rm -rf "$BG" "$BAK"; mkdir -p "$BG"
    echo "1920 1080" > "$BG/good.jpg"      # already at target
    echo "3840 2160" > "$BG/huge.jpg"      # needs resize
    echo "1920 1440" > "$BG/fourthree.png" # wrong ratio, needs resize
}

run_wp() {
    WALLPAPER_DIR="$BG" \
    WALLPAPER_BACKUP_DIR="$BAK" \
    WALLPAPER_MAGICK="$BIN/magick" \
    WALLPAPER_WIDTH=1920 WALLPAPER_HEIGHT=1080 \
    PATH="$BIN:$PATH" \
    bash "$WP" "$@" 2>&1
}

echo "=== wallpaper: list ==="
reset_fixture
output="$(run_wp list)"; code=$?
assert_exit_zero "list exits 0" "$code"
assert_output_contains "list reports the target resolution" "Target: 1920x1080" "$output"
assert_output_contains "list marks a correctly sized image ok" "good.jpg" "$output"
assert_output_contains "list flags an oversized image" "needs resize" "$output"

echo ""
echo "=== wallpaper: check ==="
reset_fixture
output="$(run_wp check)"; code=$?
assert_exit_nonzero "check exits non-zero while work is pending" "$code"
assert_output_contains "check names the count" "2 wallpaper(s) not at 1920x1080" "$output"

echo ""
echo "=== wallpaper: normalize is a dry run when asked ==="
reset_fixture
before="$(md5sum "$BG"/* | md5sum)"
output="$(WALLPAPER_DRY_RUN=1 run_wp normalize)"; code=$?
after="$(md5sum "$BG"/* | md5sum)"
assert_exit_zero "dry run exits 0" "$code"
assert_equals "dry run leaves every file byte-identical" "$before" "$after"
assert_output_contains "dry run says it would act, not that it did" "2 would be normalized" "$output"

echo ""
echo "=== wallpaper: normalize ==="
reset_fixture
output="$(run_wp normalize)"; code=$?
assert_exit_zero "normalize exits 0" "$code"
assert_output_contains "normalize reports the resize" "3840x2160 -> 1920x1080" "$output"
assert_output_contains "normalize skips the already-correct image" "2 normalized, 1 already ok" "$output"
assert_equals "oversized image is now at target" "1920 1080" "$(cat "$BG/huge.jpg")"
assert_equals "wrong-ratio image is now at target" "1920 1080" "$(cat "$BG/fourthree.png")"
assert_equals "correctly sized image was left untouched" "1920 1080" "$(cat "$BG/good.jpg")"

echo ""
echo "=== wallpaper: originals are preserved ==="
assert_equals "original of the oversized image is backed up" "3840 2160" "$(cat "$BAK/huge.jpg" 2>/dev/null)"

echo ""
echo "=== wallpaper: normalize is idempotent ==="
output="$(run_wp normalize)"; code=$?
assert_exit_zero "second normalize exits 0" "$code"
assert_output_contains "second normalize is a no-op" "0 normalized, 3 already ok" "$output"
output="$(run_wp check)"; code=$?
assert_exit_zero "check passes once everything is normalized" "$code"

echo ""
echo "=== wallpaper: empty folder and bad input ==="
rm -rf "$BG"; mkdir -p "$BG"
output="$(run_wp list)"; code=$?
assert_exit_zero "list exits 0 on an empty folder" "$code"
assert_output_contains "list says the folder is empty" "No images in" "$output"
output="$(run_wp help)"; code=$?
assert_exit_zero "help exits 0" "$code"
output="$(run_wp bogus-command)"; code=$?
assert_exit_nonzero "an unknown command exits non-zero" "$code"

finish_suite "wallpaper CLI"
