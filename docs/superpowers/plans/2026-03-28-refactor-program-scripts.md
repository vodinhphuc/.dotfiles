# Refactor Program Install Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor all 6 scripts in `scripts/programs/` to follow Ubuntu best practices: consistent bash headers, no deprecated APIs, correct idempotency guards, architecture-aware downloads, and no stray or broken code.

**Architecture:** Each script is self-contained and refactored independently. A shared test harness (`scripts/test_programs.sh`) validates idempotency guards via mocked environments (fake binaries in temp PATH, fake HOME dirs) — no sudo or network required for tests. The `set -euo pipefail` header is added to all scripts so failures are caught early and reported correctly by the orchestrator.

**Tech Stack:** Pure bash, Ubuntu 25.10

---

## File Structure

| File | Action | Key fixes |
|---|---|---|
| `scripts/test_programs.sh` | Create | Idempotency test harness for all 6 scripts |
| `scripts/programs/custome_zsh.sh` | Modify | Fix shebang, fix antigen URL, add RUNZSH=no, use `${HOME}` |
| `scripts/programs/docker.sh` | Modify | Remove dead apt-repo code, keep snap install, remove hello-world |
| `scripts/programs/miniconda.sh` | Modify | Detect arch via `uname -m`, use `curl`, use `${HOME}` |
| `scripts/programs/terminator.sh` | Modify | Fix inverted logic bug, install then write config |
| `scripts/programs/tpm.sh` | Modify | Use `${HOME}`, add `set -euo pipefail` |
| `scripts/programs/visual_code.sh` | Modify | Remove stray line, add `set -euo pipefail` |

---

### Task 1: Create program script test harness

**Files:**
- Create: `scripts/test_programs.sh`

- [ ] **Step 1: Write the test harness**

```bash
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
```

- [ ] **Step 2: Run to confirm current failure state**

```bash
bash scripts/test_programs.sh
```

Expected failures before refactoring:
- `terminator.sh does NOT say 'Already installed' when absent` → FAIL (current script incorrectly prints "Already installed" when terminator is absent)
- `custome_zsh.sh prints 'Already installed' for oh-my-zsh` → FAIL (uses `$ZSH` not `$HOME/.oh-my-zsh`)

- [ ] **Step 3: Commit the test harness**

```bash
git add scripts/test_programs.sh
git commit -m "test: add idempotency test harness for program scripts"
```

---

### Task 2: Refactor `custome_zsh.sh`

**Files:**
- Modify: `scripts/programs/custome_zsh.sh`

Issues fixed:
- `#!/bin/sh` → `#!/bin/bash` + `set -euo pipefail`
- `$ZSH` → explicit `${HOME}/.oh-my-zsh` (doesn't depend on env)
- `RUNZSH=no CHSH=no` added to oh-my-zsh installer (prevents it from spawning zsh or changing shell mid-script)
- `git.io/antigen` → direct GitHub URL (git.io was shut down in 2022)
- Zsh-specific `(( ${fpath[(Ie)...]} ))` syntax removed (not valid in bash)
- Clones conda-zsh-completion directly to target dir (no temp dir + mv)
- All paths use `${HOME}` instead of `~`

- [ ] **Step 1: Overwrite `scripts/programs/custome_zsh.sh`**

```bash
#!/bin/bash
set -euo pipefail

# Oh My ZSH
OMZ_DIR="${HOME}/.oh-my-zsh"
if [ ! -d "$OMZ_DIR" ]; then
    echo "Installing oh-my-zsh..."
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "Already installed: oh-my-zsh"
fi

# Antigen (git.io is shut down — use direct GitHub URL)
if [ ! -f "${HOME}/.antigen.zsh" ]; then
    echo "Installing Antigen..."
    curl -fsSL https://raw.githubusercontent.com/zsh-users/antigen/master/bin/antigen.zsh > "${HOME}/.antigen.zsh"
else
    echo "Already installed: ~/.antigen.zsh"
fi

# Powerlevel10k theme
P10K_DIR="${HOME}/.oh-my-zsh/custom/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
    echo "Installing powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
else
    echo "Already installed: powerlevel10k"
fi

# conda-zsh-completion plugin
CONDA_PLUGIN_DIR="${HOME}/.oh-my-zsh/custom/plugins/conda-zsh-completion"
if [ ! -d "$CONDA_PLUGIN_DIR" ]; then
    echo "Installing conda-zsh-completion..."
    git clone https://github.com/esc/conda-zsh-completion "$CONDA_PLUGIN_DIR"
else
    echo "Already installed: conda-zsh-completion"
fi
```

- [ ] **Step 2: Run tests**

```bash
bash scripts/test_programs.sh
```

Expected: `custome_zsh.sh` tests now pass. Overall failure count should decrease.

- [ ] **Step 3: Commit**

```bash
git add scripts/programs/custome_zsh.sh
git commit -m "fix: custome_zsh.sh — fix shebang, dead antigen URL, and idempotency guards"
```

---

### Task 3: Refactor `docker.sh`

**Files:**
- Modify: `scripts/programs/docker.sh`

Issues fixed:
- Removes the apt repo setup + `apt-key add` (deprecated in Ubuntu 22.04+, unused since snap is used anyway)
- Removes `apt-transport-https` install (built into modern apt)
- Removes `sudo docker run hello-world` (not needed during install, requires daemon)
- Quotes `$USER`
- Adds `set -euo pipefail`

- [ ] **Step 1: Overwrite `scripts/programs/docker.sh`**

```bash
#!/bin/bash
set -euo pipefail

if ! command -v docker &>/dev/null; then
    echo "Installing Docker..."
    sudo snap install docker
    sudo usermod -aG docker "$USER"
    echo "Docker installed. Log out and back in for group membership to take effect."
else
    echo "Already installed: docker"
fi
```

- [ ] **Step 2: Run tests**

```bash
bash scripts/test_programs.sh
```

Expected: `docker.sh` tests pass. No regression.

- [ ] **Step 3: Commit**

```bash
git add scripts/programs/docker.sh
git commit -m "fix: docker.sh — remove dead apt-repo setup, keep snap install"
```

---

### Task 4: Refactor `miniconda.sh`

**Files:**
- Modify: `scripts/programs/miniconda.sh`

Issues fixed:
- Hardcoded `x86_64` → `$(uname -m)` (supports both x86_64 and aarch64/arm64)
- `wget` → `curl -fsSL` (consistent with rest of the repo)
- `~` → `${HOME}`
- Adds `set -euo pipefail`

- [ ] **Step 1: Overwrite `scripts/programs/miniconda.sh`**

```bash
#!/bin/bash
set -euo pipefail

MINICONDA_DIR="${HOME}/miniconda3"

if [ ! -d "$MINICONDA_DIR" ]; then
    echo "Installing Miniconda3..."
    ARCH="$(uname -m)"
    INSTALLER="${MINICONDA_DIR}/miniconda.sh"
    mkdir -p "$MINICONDA_DIR"
    curl -fsSL "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${ARCH}.sh" -o "$INSTALLER"
    bash "$INSTALLER" -b -u -p "$MINICONDA_DIR"
    rm "$INSTALLER"
else
    echo "Already installed: miniconda3"
fi
```

- [ ] **Step 2: Run tests**

```bash
bash scripts/test_programs.sh
```

Expected: `miniconda.sh` tests pass.

- [ ] **Step 3: Commit**

```bash
git add scripts/programs/miniconda.sh
git commit -m "fix: miniconda.sh — detect arch, use curl, use \${HOME}"
```

---

### Task 5: Refactor `terminator.sh`

**Files:**
- Modify: `scripts/programs/terminator.sh`

Issues fixed:
- **Inverted logic bug**: original `if command -v terminator` wrote config when installed and said "Already installed" when NOT installed. Fixed to `if ! command -v terminator` to install when absent.
- Install code was commented out — uncommented.
- Config is always written/updated (idempotent operation — safe to run every time).
- Removed useless `which terminator &> /dev/null` at top.
- Used `${HOME}` and heredoc with quoted `'EOF'` to prevent variable expansion.
- Adds `set -euo pipefail`.

- [ ] **Step 1: Overwrite `scripts/programs/terminator.sh`**

```bash
#!/bin/bash
set -euo pipefail

if ! command -v terminator &>/dev/null; then
    echo "Installing Terminator..."
    sudo apt-get install -y terminator
fi

# Always write/update config (idempotent)
mkdir -p "${HOME}/.config/terminator"
cat > "${HOME}/.config/terminator/config" << 'EOF'
[global_config]

[keybindings]
[profiles]
[[default]]
  audible_bell = True
  cursor_color = "#aaaaaa"
[layouts]
[[default]]
[[[window0]]]
  type = Window
  parent = ""
  size = 1920, 1080
  position = 100:100
[[[child1]]]
  type = Terminal
  parent = window0

[plugins]
EOF
echo "Terminator config written."
```

- [ ] **Step 2: Run tests**

```bash
bash scripts/test_programs.sh
```

Expected: All `terminator.sh` tests now pass (including the previously failing "does NOT say 'Already installed' when absent" test).

- [ ] **Step 3: Commit**

```bash
git add scripts/programs/terminator.sh
git commit -m "fix: terminator.sh — fix inverted logic bug, install when absent, always write config"
```

---

### Task 6: Refactor `tpm.sh`

**Files:**
- Modify: `scripts/programs/tpm.sh`

Issues fixed:
- `~` → `${HOME}`
- Removes unused `PLUGIN_DIR` variable (used only to define `TPM_DIR`)
- Adds `set -euo pipefail`

- [ ] **Step 1: Overwrite `scripts/programs/tpm.sh`**

```bash
#!/bin/bash
set -euo pipefail

TPM_DIR="${HOME}/.tmux/plugins/tpm"

if [ ! -d "$TPM_DIR" ]; then
    echo "Installing Tmux Plugin Manager..."
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
    echo "Already installed: $TPM_DIR"
fi
```

- [ ] **Step 2: Run tests**

```bash
bash scripts/test_programs.sh
```

Expected: `tpm.sh` tests pass.

- [ ] **Step 3: Commit**

```bash
git add scripts/programs/tpm.sh
git commit -m "fix: tpm.sh — use \${HOME}, add set -euo pipefail"
```

---

### Task 7: Refactor `visual_code.sh`

**Files:**
- Modify: `scripts/programs/visual_code.sh`

Issues fixed:
- Removes stray first line `! command -v code &> /dev/null` (executed but result is discarded; causes confusion)
- Adds `set -euo pipefail`
- Consistent quoting style

- [ ] **Step 1: Overwrite `scripts/programs/visual_code.sh`**

```bash
#!/bin/bash
set -euo pipefail

if ! command -v code &>/dev/null; then
    echo "Installing Visual Studio Code..."
    sudo snap install --classic code
else
    echo "Already installed: visual studio code"
fi
```

- [ ] **Step 2: Run tests**

```bash
bash scripts/test_programs.sh
```

Expected: All tests pass, 0 failed.

- [ ] **Step 3: Commit**

```bash
git add scripts/programs/visual_code.sh
git commit -m "fix: visual_code.sh — remove stray line, add set -euo pipefail"
```

---

### Task 8: Final verification

**Files:**
- No changes expected

- [ ] **Step 1: Run full test suite**

```bash
bash scripts/test_programs.sh
```

Expected output ends with:
```
==========================================
  Test Results: N passed, 0 failed
==========================================
```

- [ ] **Step 2: Run orchestrator tests to confirm no regression**

```bash
bash scripts/test_orchestrator.sh
```

Expected:
```
==========================================
  Test Results: 10 passed, 0 failed
==========================================
```

- [ ] **Step 3: Syntax check all program scripts**

```bash
for f in scripts/programs/*.sh; do bash -n "$f" && echo "OK: $f"; done
```

Expected: `OK: scripts/programs/<name>.sh` for all 6 scripts.

- [ ] **Step 4: Commit if any uncommitted changes remain**

```bash
git status
# If clean:
echo "Nothing to commit."
# If dirty:
git add scripts/programs/
git commit -m "chore: final program script cleanup"
```
