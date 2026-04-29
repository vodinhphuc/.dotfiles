#!/bin/bash
# Idempotency test suite for scripts/programs/*.sh
# Tests run without sudo or network by mocking environments.
# Usage: bash scripts/test_programs.sh

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# --- Setup ---
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
BIN_DIR="$TEST_DIR/bin"
mkdir -p "$BIN_DIR"

# Creates a fake binary that does nothing (exit 0)
mock_cmd() {
    printf '#!/bin/bash\nexit 0\n' > "$BIN_DIR/$1"
    chmod +x "$BIN_DIR/$1"
}

# Creates a fake sudo that just runs the rest of the command as current user
mock_sudo() {
    printf '#!/bin/bash\n"$@"\n' > "$BIN_DIR/sudo"
    chmod +x "$BIN_DIR/sudo"
}

# --- docker.sh: skip when docker already in PATH ---
echo ""
echo "=== docker.sh: skip when already installed ==="
mock_cmd docker
output=$(PATH="$BIN_DIR:$PATH" bash "$DOTFILES_DIR/scripts/programs/docker.sh" 2>&1)
code=$?
assert_exit_zero "docker.sh exits 0 when already installed" "$code"
assert_output_contains "docker.sh prints 'Already installed'" "Already installed" "$output"

# --- tpm.sh: skip when TPM dir exists ---
echo ""
echo "=== tpm.sh: skip when already installed ==="
MOCK_HOME="$TEST_DIR/home_tpm"
mkdir -p "$MOCK_HOME/.tmux/plugins/tpm"
output=$(HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/tpm.sh" 2>&1)
code=$?
assert_exit_zero "tpm.sh exits 0 when already installed" "$code"
assert_output_contains "tpm.sh prints 'Already installed'" "Already installed" "$output"

# --- tpm.sh: invokes install_plugins when binary is present ---
echo ""
echo "=== tpm.sh: invokes install_plugins ==="
MOCK_HOME="$TEST_DIR/home_tpm_install"
TPM_BIN="$MOCK_HOME/.tmux/plugins/tpm/bin"
mkdir -p "$TPM_BIN"
SENTINEL="$TEST_DIR/install_plugins_called"
cat > "$TPM_BIN/install_plugins" <<EOF
#!/bin/bash
touch "$SENTINEL"
EOF
chmod +x "$TPM_BIN/install_plugins"
output=$(HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/tpm.sh" 2>&1)
code=$?
assert_exit_zero "tpm.sh exits 0 when install_plugins present" "$code"
assert_file_exists "tpm.sh invokes install_plugins" "$SENTINEL"
assert_output_contains "tpm.sh announces plugin install" "Installing tmux plugins" "$output"

# --- neovim.sh: skip when nvim already in PATH ---
echo ""
echo "=== neovim.sh: skip when already installed ==="
mock_cmd nvim
output=$(PATH="$BIN_DIR:$PATH" bash "$DOTFILES_DIR/scripts/programs/neovim.sh" 2>&1)
code=$?
assert_exit_zero "neovim.sh exits 0 when already installed" "$code"
assert_output_contains "neovim.sh prints 'Already installed: neovim'" "Already installed: neovim" "$output"
# Cleanup so later tests don't see this nvim mock
rm -f "$BIN_DIR/nvim"

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
# Logging mock for add-apt-repository
cat > "$BIN_DIR/add-apt-repository" <<EOF
#!/bin/bash
echo "add-apt-repository \$*" >> "$NEOVIM_LOG"
exit 0
EOF
chmod +x "$BIN_DIR/add-apt-repository"
# Run with isolated PATH (no nvim, no go) + mocked sudo + mocked apt commands
output=$(PATH="$BIN_DIR" /bin/bash "$DOTFILES_DIR/scripts/programs/neovim.sh" 2>&1) || true
log_content="$(cat "$NEOVIM_LOG" 2>/dev/null)"
assert_output_contains "neovim.sh adds the neovim stable PPA" "ppa:neovim-ppa/stable" "$log_content"
assert_output_contains "neovim.sh installs the neovim package" "neovim" "$log_content"
assert_output_contains "neovim.sh installs ripgrep (Telescope dep)" "ripgrep" "$log_content"
assert_output_contains "neovim.sh installs fd-find (Telescope dep)" "fd-find" "$log_content"
assert_output_contains "neovim.sh installs nodejs (for Mason-managed LSPs)" "nodejs" "$log_content"
assert_output_contains "neovim.sh notes missing go toolchain" "Mason will skip gopls" "$output"
# Cleanup: remove the logging mocks so they don't affect later tests
rm -f "$BIN_DIR/apt-get" "$BIN_DIR/add-apt-repository" "$BIN_DIR/sudo"

# --- miniconda.sh: skip when miniconda3 dir exists ---
echo ""
echo "=== miniconda.sh: skip when already installed ==="
MOCK_HOME="$TEST_DIR/home_conda"
mkdir -p "$MOCK_HOME/miniconda3"
output=$(HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/miniconda.sh" 2>&1)
code=$?
assert_exit_zero "miniconda.sh exits 0 when already installed" "$code"
assert_output_contains "miniconda.sh prints 'Already installed'" "Already installed" "$output"

# --- visual_code.sh: skip when code already in PATH ---
echo ""
echo "=== visual_code.sh: skip when already installed ==="
mock_cmd code
output=$(PATH="$BIN_DIR:$PATH" bash "$DOTFILES_DIR/scripts/programs/visual_code.sh" 2>&1)
code=$?
assert_exit_zero "visual_code.sh exits 0 when already installed" "$code"
assert_output_contains "visual_code.sh prints 'Already installed'" "Already installed" "$output"

# --- terminator.sh: should NOT say "Already installed" when terminator is absent ---
echo ""
echo "=== terminator.sh: does NOT say 'Already installed' when terminator is absent ==="
MOCK_HOME="$TEST_DIR/home_term_absent"
mkdir -p "$MOCK_HOME"
mock_sudo
mock_cmd apt-get
# Run with empty PATH (no terminator) + mocked sudo + mocked apt-get
output=$(PATH="$BIN_DIR" HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/terminator.sh" 2>&1) || true
assert_output_not_contains "terminator.sh does not say 'Already installed' when absent" "Already installed" "$output"

# --- terminator.sh: writes config when terminator is present ---
echo ""
echo "=== terminator.sh: writes config when terminator is installed ==="
mock_cmd terminator
mock_cmd update-alternatives
mock_cmd gsettings
MOCK_HOME="$TEST_DIR/home_term_present"
mkdir -p "$MOCK_HOME"
output=$(PATH="$BIN_DIR:$PATH" HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/terminator.sh" 2>&1)
code=$?
assert_exit_zero "terminator.sh exits 0 when terminator already installed" "$code"
assert_file_exists "terminator config is written" "$MOCK_HOME/.config/terminator/config"

# --- custome_zsh.sh: skips all components when already present ---
echo ""
echo "=== custome_zsh.sh: skip all components when already installed ==="
MOCK_HOME="$TEST_DIR/home_zsh"
mkdir -p "$MOCK_HOME/.oh-my-zsh/custom/themes/powerlevel10k"
mkdir -p "$MOCK_HOME/.oh-my-zsh/custom/plugins/conda-zsh-completion"
touch "$MOCK_HOME/.antigen.zsh"
output=$(HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/custome_zsh.sh" 2>&1)
code=$?
assert_exit_zero "custome_zsh.sh exits 0 when all components installed" "$code"
assert_output_contains "custome_zsh.sh prints 'Already installed' for oh-my-zsh" "Already installed: oh-my-zsh" "$output"
assert_output_contains "custome_zsh.sh prints 'Already installed' for antigen" "Already installed: ~/.antigen.zsh" "$output"
assert_output_contains "custome_zsh.sh prints 'Already installed' for powerlevel10k" "Already installed: powerlevel10k" "$output"
assert_output_contains "custome_zsh.sh prints 'Already installed' for conda-zsh-completion" "Already installed: conda-zsh-completion" "$output"

# --- Syntax checks ---
echo ""
echo "=== Syntax checks ==="
for script in "$DOTFILES_DIR"/scripts/programs/*.sh; do
    name="$(basename "$script")"
    if bash -n "$script" 2>/dev/null; then
        echo "  PASS: $name syntax OK"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name has syntax errors"
        bash -n "$script" 2>&1 | sed 's/^/        /'
        FAIL=$((FAIL + 1))
    fi
done

# --- Summary ---
echo ""
echo "=========================================="
echo "  Test Results: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ] || exit 1
