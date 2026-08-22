#!/bin/bash
# Tests for scripts/programs/nerd_font.sh
#
# Runnable on its own:  bash scripts/tests/test_nerd_font.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- nerd_font.sh: skip when the font is already registered with fontconfig ---
echo ""
echo "=== nerd_font.sh: skip when already installed ==="
NERD_SKIP_LOG="$TEST_DIR/nerd_skip_calls.log"
: > "$NERD_SKIP_LOG"
MOCK_HOME="$TEST_DIR/home_nerd_skip"
mkdir -p "$MOCK_HOME"
# The mock must emit MANY lines after the match. A `grep -q` guard exits on the
# first hit and SIGPIPEs the producer; under `set -o pipefail` that fails the
# whole pipeline and the guard misfires, reinstalling on every run. A one-line
# mock cannot reproduce it -- the real fc-list emits ~630 lines.
cat > "$BIN_DIR/fc-list" <<'FCEOF'
#!/bin/bash
echo "/home/u/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf: JetBrainsMono Nerd Font Mono:style=Regular"
i=0
while [ $i -lt 20000 ]; do
    echo "/usr/share/fonts/filler-$i.ttf: Filler Face $i:style=Regular"
    i=$((i + 1))
done
FCEOF
chmod +x "$BIN_DIR/fc-list"
mock_logging_cmds "$NERD_SKIP_LOG" curl unzip fc-cache
for bin in grep mkdir mktemp rm find cp cat; do ln -sf "$(command -v "$bin")" "$BIN_DIR/$bin"; done
output=$(PATH="$BIN_DIR" HOME="$MOCK_HOME" /bin/bash "$DOTFILES_DIR/scripts/programs/nerd_font.sh" 2>&1)
code=$?
log_content="$(cat "$NERD_SKIP_LOG" 2>/dev/null)"
assert_exit_zero "nerd_font.sh exits 0 when already installed" "$code"
assert_output_contains "nerd_font.sh prints 'Already installed'" "Already installed: JetBrainsMono Nerd Font" "$output"
assert_output_not_contains "nerd_font.sh does not re-download the font" "curl" "$log_content"
assert_output_contains "nerd_font.sh still prints the manual follow-up steps" "have_nerd_font = true" "$output"

# --- nerd_font.sh: downloads and installs when the font is absent ---
echo ""
echo "=== nerd_font.sh: installs when absent ==="
NERD_LOG="$TEST_DIR/nerd_calls.log"
: > "$NERD_LOG"
MOCK_HOME="$TEST_DIR/home_nerd_install"
mkdir -p "$MOCK_HOME"
printf '#!/bin/bash\nexit 0\n' > "$BIN_DIR/fc-list"   # no fonts registered
chmod +x "$BIN_DIR/fc-list"
mock_logging_cmds "$NERD_LOG" curl unzip fc-cache
output=$(PATH="$BIN_DIR" HOME="$MOCK_HOME" /bin/bash "$DOTFILES_DIR/scripts/programs/nerd_font.sh" 2>&1)
code=$?
log_content="$(cat "$NERD_LOG" 2>/dev/null)"
assert_exit_zero "nerd_font.sh exits 0 when installing" "$code"
assert_output_contains "nerd_font.sh downloads from the nerd-fonts releases" "ryanoasis/nerd-fonts/releases" "$log_content"
assert_output_contains "nerd_font.sh refreshes the fontconfig cache" "fc-cache -f" "$log_content"
assert_dir_exists "nerd_font.sh creates the user font dir" "$MOCK_HOME/.local/share/fonts"
assert_output_not_contains "nerd_font.sh never uses sudo" "sudo" "$log_content"

# --- nerd_font.sh: font name is overridable ---
echo ""
echo "=== nerd_font.sh: honors NERD_FONT_NAME override ==="
NERD_ALT_LOG="$TEST_DIR/nerd_alt_calls.log"
: > "$NERD_ALT_LOG"
MOCK_HOME="$TEST_DIR/home_nerd_alt"
mkdir -p "$MOCK_HOME"
mock_logging_cmds "$NERD_ALT_LOG" curl unzip fc-cache
output=$(PATH="$BIN_DIR" HOME="$MOCK_HOME" NERD_FONT_NAME=FiraCode NERD_FONT_MATCH="FiraCode Nerd Font" \
    /bin/bash "$DOTFILES_DIR/scripts/programs/nerd_font.sh" 2>&1)
log_content="$(cat "$NERD_ALT_LOG" 2>/dev/null)"
assert_output_contains "nerd_font.sh downloads the overridden font" "FiraCode.zip" "$log_content"
assert_output_not_contains "nerd_font.sh does not download the default font" "JetBrainsMono.zip" "$log_content"
rm -f "$BIN_DIR/fc-list" "$BIN_DIR/curl" "$BIN_DIR/unzip" "$BIN_DIR/fc-cache" \
      "$BIN_DIR/grep" "$BIN_DIR/mkdir" "$BIN_DIR/mktemp" "$BIN_DIR/rm" \
      "$BIN_DIR/find" "$BIN_DIR/cp" "$BIN_DIR/cat"

finish_suite "nerd_font.sh"
