#!/bin/bash
# Tests for scripts/programs/fzf.sh
#
# Runnable on its own:  bash scripts/tests/test_fzf.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

FZF_SCRIPT="$DOTFILES_DIR/scripts/programs/fzf.sh"

# A stand-in for a modern fzf: `fzf --zsh` prints the integration snippet.
mock_fzf_with_zsh_flag() {
    cat > "$BIN_DIR/fzf" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "--zsh" ]; then
    echo "# generated-by-fzf--zsh"
    exit 0
fi
exit 0
EOF
    chmod +x "$BIN_DIR/fzf"
}

# A stand-in for fzf < 0.48, which has no --zsh flag at all.
mock_fzf_without_zsh_flag() {
    cat > "$BIN_DIR/fzf" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "--zsh" ]; then
    echo "unknown option: --zsh" >&2
    exit 2
fi
exit 0
EOF
    chmod +x "$BIN_DIR/fzf"
}

# The snippet files Debian/Ubuntu ship for fzf builds that predate --zsh.
seed_examples_dir() {
    local dir="$1"
    mkdir -p "$dir"
    echo "# from-key-bindings.zsh" > "$dir/key-bindings.zsh"
    echo "# from-completion.zsh" > "$dir/completion.zsh"
}

# --- fzf.sh: skip when fzf and fd are already in PATH ---
echo ""
echo "=== fzf.sh: skip when already installed ==="
mock_fzf_with_zsh_flag
mock_cmd fdfind
CONFIG_DIR="$TEST_DIR/config_skip"
output=$(PATH="$BIN_DIR:$PATH" FZF_CONFIG_DIR="$CONFIG_DIR" bash "$FZF_SCRIPT" 2>&1)
code=$?
assert_exit_zero "fzf.sh exits 0 when already installed" "$code"
assert_output_contains "fzf.sh prints 'Already installed: fzf'" "Already installed: fzf" "$output"
assert_output_contains "fzf.sh prints 'Already installed: fd-find'" "Already installed: fd-find" "$output"
# The integration file is regenerated unconditionally (like uv.sh's completions)
# so it tracks the installed fzf across upgrades instead of going stale.
assert_file_exists "fzf.sh generates the zsh integration" "$CONFIG_DIR/fzf.zsh"
assert_file_contains "integration comes from 'fzf --zsh' when supported" "$CONFIG_DIR/fzf.zsh" "generated-by-fzf--zsh"

# --- fzf.sh: regenerates a stale integration file ---
echo ""
echo "=== fzf.sh: regenerates an existing integration file ==="
echo "# stale-content-from-an-older-fzf" > "$CONFIG_DIR/fzf.zsh"
output=$(PATH="$BIN_DIR:$PATH" FZF_CONFIG_DIR="$CONFIG_DIR" bash "$FZF_SCRIPT" 2>&1)
code=$?
assert_exit_zero "fzf.sh exits 0 on a re-run" "$code"
assert_file_contains "re-run refreshes the integration" "$CONFIG_DIR/fzf.zsh" "generated-by-fzf--zsh"
if grep -q "stale-content-from-an-older-fzf" "$CONFIG_DIR/fzf.zsh"; then
    echo "  FAIL: re-run should replace stale content, not append to it"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: re-run replaces stale content rather than appending"
    PASS=$((PASS + 1))
fi
rm -f "$BIN_DIR/fzf" "$BIN_DIR/fdfind"

# --- fzf.sh: falls back to the packaged snippets when --zsh is unsupported ---
echo ""
echo "=== fzf.sh: falls back to packaged snippets on fzf < 0.48 ==="
mock_fzf_without_zsh_flag
mock_cmd fdfind
CONFIG_DIR="$TEST_DIR/config_fallback"
EXAMPLES_DIR="$TEST_DIR/examples"
seed_examples_dir "$EXAMPLES_DIR"
output=$(PATH="$BIN_DIR:$PATH" FZF_CONFIG_DIR="$CONFIG_DIR" FZF_EXAMPLES_DIR="$EXAMPLES_DIR" \
    bash "$FZF_SCRIPT" 2>&1)
code=$?
assert_exit_zero "fzf.sh exits 0 when falling back" "$code"
assert_file_exists "fallback still writes an integration file" "$CONFIG_DIR/fzf.zsh"
assert_file_contains "fallback includes key-bindings.zsh" "$CONFIG_DIR/fzf.zsh" "from-key-bindings.zsh"
assert_file_contains "fallback includes completion.zsh" "$CONFIG_DIR/fzf.zsh" "from-completion.zsh"

# --- fzf.sh: a failed regeneration must not destroy a working file ---
# terminator.sh once clobbered a hand-edited config on every install.sh run;
# the same mistake here would silently drop the user's key bindings.
echo ""
echo "=== fzf.sh: keeps the existing integration when generation fails ==="
CONFIG_DIR="$TEST_DIR/config_nogen"
mkdir -p "$CONFIG_DIR"
echo "# previously-working-integration" > "$CONFIG_DIR/fzf.zsh"
output=$(PATH="$BIN_DIR:$PATH" FZF_CONFIG_DIR="$CONFIG_DIR" FZF_EXAMPLES_DIR="$TEST_DIR/does_not_exist" \
    bash "$FZF_SCRIPT" 2>&1)
code=$?
assert_exit_zero "fzf.sh exits 0 rather than failing install.sh" "$code"
assert_output_contains "fzf.sh warns when it cannot generate" "could not generate" "$output"
assert_file_contains "existing integration survives a failed regeneration" "$CONFIG_DIR/fzf.zsh" "previously-working-integration"
rm -f "$BIN_DIR/fzf" "$BIN_DIR/fdfind"

# --- fzf.sh: installs the packages it needs ---
# This machine already has fdfind (and will have fzf once this lands), so a
# PATH of "$BIN_DIR:$PATH" would make both look installed and the assertions
# would quietly test nothing. Instead the script runs against a PATH holding
# only the mocks plus the handful of binaries it actually calls.
echo ""
echo "=== fzf.sh: installs fzf and fd-find when missing ==="
mock_sudo
APT_LOG="$TEST_DIR/apt_install.log"
mock_logging_cmds "$APT_LOG" apt-get
ISO_BIN="$TEST_DIR/iso_bin"
mkdir -p "$ISO_BIN"
cp "$BIN_DIR/sudo" "$BIN_DIR/apt-get" "$ISO_BIN/"
for tool in bash mkdir chmod mv rm cat; do
    ln -sf "$(command -v "$tool")" "$ISO_BIN/$tool"
done
CONFIG_DIR="$TEST_DIR/config_install"
output=$(PATH="$ISO_BIN" FZF_CONFIG_DIR="$CONFIG_DIR" \
    FZF_EXAMPLES_DIR="$TEST_DIR/does_not_exist" bash "$FZF_SCRIPT" 2>&1)
code=$?
assert_exit_zero "fzf.sh exits 0 on a fresh install" "$code"
assert_file_contains "fzf.sh apt-installs fzf" "$APT_LOG" "install -y fzf"
# Ubuntu ships fd as `fd-find`/`fdfind` because plain `fd` is a different package.
assert_file_contains "fzf.sh apt-installs fd-find" "$APT_LOG" "install -y fd-find"
rm -f "$BIN_DIR/sudo" "$BIN_DIR/apt-get"

# --- .zshrc wiring: the dotfile and the install script must agree ---
# The script writes ~/.config/fzf/fzf.zsh; if .zshrc sources some other path,
# every key binding silently does nothing and there is no error to notice.
echo ""
echo "=== .zshrc: sources the integration the script generates ==="
ZSHRC="$DOTFILES_DIR/.zshrc"
assert_file_contains ".zshrc sources ~/.config/fzf/fzf.zsh" "$ZSHRC" ".config/fzf/fzf.zsh"
assert_file_contains ".zshrc points FZF_DEFAULT_COMMAND at fdfind" "$ZSHRC" "FZF_DEFAULT_COMMAND"
assert_file_contains ".zshrc uses fdfind (not fd) for the default command" "$ZSHRC" "fdfind"
assert_file_contains ".zshrc themes fzf to match the terminal" "$ZSHRC" "FZF_DEFAULT_OPTS"
assert_file_contains ".zshrc previews files on Ctrl-T" "$ZSHRC" "FZF_CTRL_T_OPTS"
assert_file_contains ".zshrc previews directories on Alt-C" "$ZSHRC" "FZF_ALT_C_OPTS"

finish_suite "fzf.sh"
