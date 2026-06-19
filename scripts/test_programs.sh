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
# Run with isolated PATH (no nvim, no go) + mocked sudo + mocked snap/apt/npm
output=$(PATH="$BIN_DIR" /bin/bash "$DOTFILES_DIR/scripts/programs/neovim.sh" 2>&1) || true
log_content="$(cat "$NEOVIM_LOG" 2>/dev/null)"
assert_output_contains "neovim.sh installs nvim via snap with classic confinement" "snap install nvim --classic" "$log_content"
assert_output_contains "neovim.sh installs ripgrep (Telescope dep)" "ripgrep" "$log_content"
assert_output_contains "neovim.sh installs fd-find (Telescope dep)" "fd-find" "$log_content"
assert_output_contains "neovim.sh installs nodejs (for Mason-managed LSPs)" "nodejs" "$log_content"
assert_output_contains "neovim.sh installs tree-sitter-cli via npm" "npm install -g tree-sitter-cli" "$log_content"
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
output=$(PATH="$BIN_DIR" ENVIRONMENT=wsl /bin/bash "$DOTFILES_DIR/scripts/programs/neovim.sh" 2>&1) || true
log_content="$(cat "$NEOVIM_WSL_LOG" 2>/dev/null)"
assert_output_contains "WSL neovim.sh downloads the official release tarball" "neovim/releases/latest/download" "$log_content"
assert_output_contains "WSL neovim.sh symlinks nvim onto PATH" "ln -sf /opt/nvim/bin/nvim" "$log_content"
assert_output_not_contains "WSL neovim.sh does NOT use snap" "snap install" "$log_content"
assert_output_contains "WSL neovim.sh still installs ripgrep dep" "ripgrep" "$log_content"
rm -f "$BIN_DIR/sudo" "$BIN_DIR/curl" "$BIN_DIR/apt-get" "$BIN_DIR/npm" "$BIN_DIR/uname" "$BIN_DIR/mktemp" "$BIN_DIR/rm"

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

# --- uv.sh: skip when uv already in PATH, still (re)generates completions ---
echo ""
echo "=== uv.sh: skip when already installed ==="
mock_cmd uv
mock_cmd uvx
MOCK_HOME="$TEST_DIR/home_uv"
mkdir -p "$MOCK_HOME"
output=$(PATH="$BIN_DIR:$PATH" HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/uv.sh" 2>&1)
code=$?
assert_exit_zero "uv.sh exits 0 when already installed" "$code"
assert_output_contains "uv.sh prints 'Already installed: uv'" "Already installed: uv" "$output"
assert_file_exists "uv.sh generates uv.zsh completion" "$MOCK_HOME/.config/uv/uv.zsh"
assert_file_exists "uv.sh generates uvx.zsh completion" "$MOCK_HOME/.config/uv/uvx.zsh"
rm -f "$BIN_DIR/uv" "$BIN_DIR/uvx"

# --- glow.sh: skip when glow already in PATH ---
echo ""
echo "=== glow.sh: skip when glow already installed ==="
mock_cmd glow
mock_cmd batcat   # also bypass the bat install path so this test isolates glow
output=$(PATH="$BIN_DIR:$PATH" bash "$DOTFILES_DIR/scripts/programs/glow.sh" 2>&1)
code=$?
assert_exit_zero "glow.sh exits 0 when glow already installed" "$code"
assert_output_contains "glow.sh prints 'Already installed: glow'" "Already installed: glow" "$output"
assert_output_contains "glow.sh prints 'Already installed: bat'" "Already installed: bat" "$output"
rm -f "$BIN_DIR/glow" "$BIN_DIR/batcat"

# --- glow.sh: skip when batcat already in PATH ---
echo ""
echo "=== glow.sh: skip when bat already installed ==="
mock_cmd batcat
mock_cmd glow
output=$(PATH="$BIN_DIR:$PATH" bash "$DOTFILES_DIR/scripts/programs/glow.sh" 2>&1)
code=$?
assert_exit_zero "glow.sh exits 0 when bat already installed" "$code"
assert_output_contains "glow.sh (bat-block) prints 'Already installed: glow'" "Already installed: glow" "$output"
assert_output_contains "glow.sh prints 'Already installed: bat'" "Already installed: bat" "$output"
rm -f "$BIN_DIR/glow" "$BIN_DIR/batcat"

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

# --- fan_control.sh: skip when already installed ---
echo ""
echo "=== fan_control.sh: skip when already installed ==="
mock_sudo
# dpkg-query mock that reports both packages installed
cat > "$BIN_DIR/dpkg-query" <<'EOF'
#!/bin/bash
# Args we care about: -W -f=${Status} <pkg>
exit 0
EOF
chmod +x "$BIN_DIR/dpkg-query"
MOCK_HOME="$TEST_DIR/home_fan_skip"
mkdir -p "$MOCK_HOME/etc/modules-load.d"
touch "$MOCK_HOME/etc/modules-load.d/nct6775.conf"
output=$(PATH="$BIN_DIR:$PATH" \
    FAN_MODULES_LOAD_DIR="$MOCK_HOME/etc/modules-load.d" \
    FAN_FORCE_PKG_INSTALLED=1 \
    bash "$DOTFILES_DIR/scripts/programs/fan_control.sh" 2>&1)
code=$?
assert_exit_zero "fan_control.sh exits 0 when already installed" "$code"
assert_output_contains "fan_control.sh prints 'Already installed: fan_control'" "Already installed: fan_control" "$output"
rm -f "$BIN_DIR/dpkg-query" "$BIN_DIR/sudo"

# --- fan_control.sh: installs packages, loads module, writes modules-load.d ---
echo ""
echo "=== fan_control.sh: installs packages and persists module ==="
FAN_LOG="$TEST_DIR/fan_calls.log"
: > "$FAN_LOG"
mock_sudo
cat > "$BIN_DIR/apt-get" <<EOF
#!/bin/bash
echo "apt-get \$*" >> "$FAN_LOG"
exit 0
EOF
chmod +x "$BIN_DIR/apt-get"
cat > "$BIN_DIR/modprobe" <<EOF
#!/bin/bash
echo "modprobe \$*" >> "$FAN_LOG"
exit 0
EOF
chmod +x "$BIN_DIR/modprobe"
# Mock tee to write file and log call
cat > "$BIN_DIR/tee" <<EOF
#!/bin/bash
echo "tee \$*" >> "$FAN_LOG"
/bin/cat > "\$1"
exit 0
EOF
chmod +x "$BIN_DIR/tee"
# Mock cat to read stdin and output (for the heredoc in fan_control.sh)
cat > "$BIN_DIR/cat" <<EOF
#!/bin/bash
/bin/cat "\$@"
exit 0
EOF
chmod +x "$BIN_DIR/cat"
MOCK_HOME="$TEST_DIR/home_fan_install"
mkdir -p "$MOCK_HOME/etc/modules-load.d"
output=$(PATH="$BIN_DIR" \
    FAN_MODULES_LOAD_DIR="$MOCK_HOME/etc/modules-load.d" \
    FAN_FORCE_PKG_INSTALLED=0 \
    /bin/bash "$DOTFILES_DIR/scripts/programs/fan_control.sh" 2>&1) || true
log_content="$(cat "$FAN_LOG" 2>/dev/null)"
assert_output_contains "fan_control.sh apt-installs lm-sensors" "lm-sensors" "$log_content"
assert_output_contains "fan_control.sh apt-installs fancontrol" "fancontrol" "$log_content"
assert_output_contains "fan_control.sh modprobes nct6775" "modprobe nct6775" "$log_content"
assert_file_exists "fan_control.sh writes /etc/modules-load.d/nct6775.conf" "$MOCK_HOME/etc/modules-load.d/nct6775.conf"
assert_output_contains "fan_control.sh prints next-steps pointer" "docs/guides/fans.md" "$output"
rm -f "$BIN_DIR/apt-get" "$BIN_DIR/modprobe" "$BIN_DIR/tee" "$BIN_DIR/cat" "$BIN_DIR/sudo"

# --- fan_control.sh: skip via real dpkg-query branch ---
echo ""
echo "=== fan_control.sh: skip when dpkg-query reports installed ==="
mock_sudo
cat > "$BIN_DIR/dpkg-query" <<'EOF'
#!/bin/bash
echo "install ok installed"
exit 0
EOF
chmod +x "$BIN_DIR/dpkg-query"
MOCK_HOME="$TEST_DIR/home_fan_dpkg"
mkdir -p "$MOCK_HOME/etc/modules-load.d"
touch "$MOCK_HOME/etc/modules-load.d/nct6775.conf"
output=$(PATH="$BIN_DIR:$PATH" \
    FAN_MODULES_LOAD_DIR="$MOCK_HOME/etc/modules-load.d" \
    bash "$DOTFILES_DIR/scripts/programs/fan_control.sh" 2>&1)
code=$?
assert_exit_zero "fan_control.sh exits 0 when dpkg-query reports installed" "$code"
assert_output_contains "fan_control.sh skips via real dpkg-query path" "Already installed: fan_control" "$output"
rm -f "$BIN_DIR/dpkg-query" "$BIN_DIR/sudo"

# --- fan CLI: dispatch to dedicated test file ---
echo ""
echo "=== fan CLI ==="
if bash "$DOTFILES_DIR/scripts/test_fan_cli.sh"; then
    echo "  PASS: fan CLI suite"
    PASS=$((PASS + 1))
else
    echo "  FAIL: fan CLI suite"
    FAIL=$((FAIL + 1))
fi

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
