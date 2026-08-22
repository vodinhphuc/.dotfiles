#!/bin/bash
# Tests for scripts/programs/neovim.sh
#
# Runnable on its own:  bash scripts/tests/test_neovim.sh
# Or as part of everything:  bash scripts/test_programs.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/lib/assertions.sh
source "$TESTS_DIR/lib/assertions.sh"
# shellcheck source=scripts/tests/lib/mocks.sh
source "$TESTS_DIR/lib/mocks.sh"

# --- neovim.sh: skip every step when nvim, deps, and tree-sitter are present ---
echo ""
echo "=== neovim.sh: skip when already installed ==="
NEOVIM_SKIP_LOG="$TEST_DIR/neovim_skip_calls.log"
: > "$NEOVIM_SKIP_LOG"
MOCK_HOME="$TEST_DIR/home_nvim_skip"
mkdir -p "$MOCK_HOME"
mock_cmd nvim
mock_cmd tree-sitter
mock_dpkg_query_all_installed
mock_logging_cmds "$NEOVIM_SKIP_LOG" sudo apt-get npm snap
output=$(PATH="$BIN_DIR" HOME="$MOCK_HOME" /bin/bash "$DOTFILES_DIR/scripts/programs/neovim.sh" 2>&1)
code=$?
log_content="$(cat "$NEOVIM_SKIP_LOG" 2>/dev/null)"
assert_exit_zero "neovim.sh exits 0 when already installed" "$code"
assert_output_contains "neovim.sh prints 'Already installed: neovim'" "Already installed: neovim" "$output"
assert_output_contains "neovim.sh prints 'Already installed: tree-sitter CLI'" "Already installed: tree-sitter CLI" "$output"
assert_output_not_contains "neovim.sh does not reinstall nvim when present" "snap install" "$log_content"
assert_output_not_contains "neovim.sh does not reinstall tree-sitter when present" "npm install" "$log_content"
rm -f "$BIN_DIR/nvim" "$BIN_DIR/tree-sitter" "$BIN_DIR/dpkg-query" \
      "$BIN_DIR/sudo" "$BIN_DIR/apt-get" "$BIN_DIR/npm" "$BIN_DIR/snap"

# --- neovim.sh: installs tree-sitter CLI even when nvim is already present ---
# Regression guard. The script used to `exit 0` on `command -v nvim`, which made
# every step below it unreachable on a machine that already had nvim. The
# tree-sitter CLI was added after those machines were provisioned, so it never
# installed, and nvim-treesitter failed to compile every parser on startup with
# "ENOENT: no such file or directory (cmd): 'tree-sitter'".
echo ""
echo "=== neovim.sh: installs tree-sitter CLI when nvim present but CLI missing ==="
NEOVIM_TS_LOG="$TEST_DIR/neovim_ts_calls.log"
: > "$NEOVIM_TS_LOG"
MOCK_HOME="$TEST_DIR/home_nvim_ts"
mkdir -p "$MOCK_HOME"
mock_cmd nvim
mock_dpkg_query_all_installed
mock_logging_cmds "$NEOVIM_TS_LOG" sudo apt-get npm snap
output=$(PATH="$BIN_DIR" HOME="$MOCK_HOME" /bin/bash "$DOTFILES_DIR/scripts/programs/neovim.sh" 2>&1)
code=$?
log_content="$(cat "$NEOVIM_TS_LOG" 2>/dev/null)"
assert_exit_zero "neovim.sh exits 0 when nvim present but tree-sitter missing" "$code"
assert_output_contains "neovim.sh installs tree-sitter CLI despite nvim being present" "npm install -g --prefix" "$log_content"
assert_output_contains "neovim.sh installs the tree-sitter-cli package" "tree-sitter-cli" "$log_content"
assert_output_not_contains "neovim.sh does not reinstall nvim when present" "snap install" "$log_content"
assert_output_not_contains "neovim.sh installs tree-sitter CLI without sudo" "sudo npm" "$log_content"
rm -f "$BIN_DIR/nvim" "$BIN_DIR/dpkg-query" \
      "$BIN_DIR/sudo" "$BIN_DIR/apt-get" "$BIN_DIR/npm" "$BIN_DIR/snap"

# --- neovim.sh: installs neovim and deps when absent ---
echo ""
echo "=== neovim.sh: installs neovim and deps when absent ==="
NEOVIM_LOG="$TEST_DIR/neovim_calls.log"
: > "$NEOVIM_LOG"
mock_sudo
# Logging mock for apt-get (records argv so we can assert what was installed)
cat > "$BIN_DIR/apt-get" <<EOF
#!/bin/bash
echo "apt-get \$*" >> "$NEOVIM_LOG"
exit 0
EOF
chmod +x "$BIN_DIR/apt-get"
# Logging mock for snap (records argv so we can assert nvim was installed via snap)
cat > "$BIN_DIR/snap" <<EOF
#!/bin/bash
echo "snap \$*" >> "$NEOVIM_LOG"
exit 0
EOF
chmod +x "$BIN_DIR/snap"
# Logging mock for npm (records argv so we can assert tree-sitter-cli was installed)
cat > "$BIN_DIR/npm" <<EOF
#!/bin/bash
echo "npm \$*" >> "$NEOVIM_LOG"
exit 0
EOF
chmod +x "$BIN_DIR/npm"
# Run with isolated PATH (no nvim, no go) + mocked sudo + mocked snap/apt/npm.
# HOME is isolated too: the script prepends $HOME/.npm-global/bin to PATH, so a
# real tree-sitter in the developer's home would otherwise mask the install step.
MOCK_HOME="$TEST_DIR/home_nvim_absent"
mkdir -p "$MOCK_HOME"
output=$(PATH="$BIN_DIR" HOME="$MOCK_HOME" /bin/bash "$DOTFILES_DIR/scripts/programs/neovim.sh" 2>&1) || true
log_content="$(cat "$NEOVIM_LOG" 2>/dev/null)"
assert_output_contains "neovim.sh installs nvim via snap with classic confinement" "snap install nvim --classic" "$log_content"
assert_output_contains "neovim.sh installs ripgrep (Telescope dep)" "ripgrep" "$log_content"
assert_output_contains "neovim.sh installs fd-find (Telescope dep)" "fd-find" "$log_content"
assert_output_contains "neovim.sh installs nodejs (for Mason-managed LSPs)" "nodejs" "$log_content"
assert_output_contains "neovim.sh installs tree-sitter-cli via npm" "npm install -g --prefix" "$log_content"
assert_output_contains "neovim.sh installs the tree-sitter-cli package" "tree-sitter-cli" "$log_content"
assert_output_contains "neovim.sh notes missing go toolchain" "Mason will skip gopls" "$output"
# Cleanup: remove the logging mocks so they don't affect later tests
rm -f "$BIN_DIR/apt-get" "$BIN_DIR/snap" "$BIN_DIR/npm" "$BIN_DIR/sudo"

# --- neovim.sh: WSL target installs from tarball, never snap ---
echo ""
echo "=== neovim.sh: WSL installs from release tarball, not snap ==="
NEOVIM_WSL_LOG="$TEST_DIR/neovim_wsl_calls.log"
: > "$NEOVIM_WSL_LOG"
# sudo mock that LOGS only (never executes) so /opt is never touched
for cmd in sudo curl apt-get npm; do
    cat > "$BIN_DIR/$cmd" <<EOF
#!/bin/bash
echo "$cmd \$*" >> "$NEOVIM_WSL_LOG"
exit 0
EOF
    chmod +x "$BIN_DIR/$cmd"
done
# The WSL branch needs real uname/mktemp/rm; symlink them into BIN_DIR so we can
# keep PATH isolated (PATH=$BIN_DIR only) and hide any real nvim on the system.
for bin in uname mktemp rm; do ln -sf "$(command -v "$bin")" "$BIN_DIR/$bin"; done
MOCK_HOME="$TEST_DIR/home_nvim_wsl"
mkdir -p "$MOCK_HOME"
output=$(PATH="$BIN_DIR" HOME="$MOCK_HOME" ENVIRONMENT=wsl /bin/bash "$DOTFILES_DIR/scripts/programs/neovim.sh" 2>&1) || true
log_content="$(cat "$NEOVIM_WSL_LOG" 2>/dev/null)"
assert_output_contains "WSL neovim.sh downloads the official release tarball" "neovim/releases/latest/download" "$log_content"
assert_output_contains "WSL neovim.sh symlinks nvim onto PATH" "ln -sf /opt/nvim/bin/nvim" "$log_content"
assert_output_not_contains "WSL neovim.sh does NOT use snap" "snap install" "$log_content"
assert_output_contains "WSL neovim.sh still installs ripgrep dep" "ripgrep" "$log_content"
rm -f "$BIN_DIR/sudo" "$BIN_DIR/curl" "$BIN_DIR/apt-get" "$BIN_DIR/npm" "$BIN_DIR/uname" "$BIN_DIR/mktemp" "$BIN_DIR/rm"

finish_suite "neovim.sh"
