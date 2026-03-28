# Resilient Install Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden `scripts/install.sh` into a resilient orchestrator with idempotency, error isolation, resume capability, and a clear summary report.

**Architecture:** `install.sh` is rewritten as an orchestrator with a `run_step()` function that wraps each program script in a subshell, tracks completion in `.install_state`, logs failures to `.install_errors`, and streams all output to `.install.log`. The main body is guarded with `BASH_SOURCE` so functions can be sourced independently for testing.

**Tech Stack:** Pure bash (no new dependencies)

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/install.sh` | Modify (full rewrite) | Orchestrator: state tracking, error isolation, summary |
| `scripts/test_orchestrator.sh` | Create | Test `run_step` behavior in isolation |
| `.gitignore` | Create | Exclude `.install_state`, `.install_errors`, `.install.log` |

---

### Task 1: Add `.gitignore`

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Create `.gitignore`**

```
.install_state
.install_errors
.install.log
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: ignore install state and log files"
```

---

### Task 2: Write failing tests for `run_step`

**Files:**
- Create: `scripts/test_orchestrator.sh`

- [ ] **Step 1: Write the test script**

```bash
#!/bin/bash
# Tests for run_step orchestrator function in install.sh
# Usage: bash scripts/test_orchestrator.sh

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

# --- Test helpers ---

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

assert_file_contains() {
    local desc="$1" file="$2" content="$3"
    if grep -qx "$content" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        expected '$content' in $file"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_not_contains() {
    local desc="$1" file="$2" content="$3"
    if ! grep -qx "$content" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "        expected '$content' NOT in $file"
        FAIL=$((FAIL + 1))
    fi
}

# --- Setup: override state file paths and source functions ---

TEST_DIR="$(mktemp -d)"
trap "rm -rf $TEST_DIR" EXIT

export STATE_FILE="$TEST_DIR/.install_state"
export ERRORS_FILE="$TEST_DIR/.install_errors"
export LOG_FILE="$TEST_DIR/.install.log"
touch "$ERRORS_FILE"

# Source only the functions (not main body) from install.sh
# Then disable set -e so test assertions can handle failures gracefully
source "$DOTFILES_DIR/scripts/install.sh"
set +e

# --- Tests ---

echo ""
echo "=== Test: successful step is recorded in state file ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_ok" <(echo "exit 0")
assert_file_contains "state file contains test_ok" "$STATE_FILE" "test_ok"
assert_file_not_contains "errors file does not contain test_ok" "$ERRORS_FILE" "test_ok"
assert_equals "STEPS_OK has test_ok" "test_ok" "${STEPS_OK[0]:-}"

echo ""
echo "=== Test: already-completed step is skipped ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_ok" <(echo "exit 0")
assert_equals "STEPS_SKIP has test_ok" "test_ok" "${STEPS_SKIP[0]:-}"
assert_equals "STEPS_OK is empty" "" "${STEPS_OK[0]:-}"

echo ""
echo "=== Test: failing step is recorded in errors file ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_fail" <(echo "exit 1")
assert_file_contains "errors file contains test_fail" "$ERRORS_FILE" "test_fail"
assert_file_not_contains "state file does not contain test_fail" "$STATE_FILE" "test_fail"
assert_equals "STEPS_FAIL has test_fail" "test_fail" "${STEPS_FAIL[0]:-}"

echo ""
echo "=== Test: failure in one step does not abort subsequent steps ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_abort_check" <(echo "exit 0")
assert_file_contains "state file contains test_abort_check after prior failure" "$STATE_FILE" "test_abort_check"

echo ""
echo "=== Test: exit inside script does not kill orchestrator ==="
STEPS_OK=(); STEPS_SKIP=(); STEPS_FAIL=()
run_step "test_exit_trap" <(printf '#!/bin/bash\nexit 42')
assert_equals "orchestrator still running after exit 42" "test_exit_trap" "${STEPS_FAIL[0]:-}"

# --- Summary ---
echo ""
echo "=========================================="
echo "  Test Results: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run to verify tests fail (functions not defined yet)**

```bash
bash scripts/test_orchestrator.sh
```

Expected: error like `run_step: command not found` or `source: ... no such file` because `install.sh` does not have the function yet.

- [ ] **Step 3: Commit the failing tests**

```bash
git add scripts/test_orchestrator.sh
git commit -m "test: add orchestrator tests for run_step behavior"
```

---

### Task 3: Implement `run_step` with `BASH_SOURCE` guard

**Files:**
- Modify: `scripts/install.sh`

- [ ] **Step 1: Add the `BASH_SOURCE` guard and `run_step` to `install.sh`**

Add this block **at the top** of `install.sh` (after `#!/bin/bash`), replacing the entire file:

```bash
#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${STATE_FILE:-$DOTFILES_DIR/.install_state}"
ERRORS_FILE="${ERRORS_FILE:-$DOTFILES_DIR/.install_errors}"
LOG_FILE="${LOG_FILE:-$DOTFILES_DIR/.install.log}"

declare -a STEPS_OK=()
declare -a STEPS_SKIP=()
declare -a STEPS_FAIL=()

# --- Functions ---

function install_pkg {
    if ! command -v "$1" &>/dev/null; then
        echo "Installing: $1..."
        sudo apt install -y "$1"
    else
        echo "Already installed: $1"
    fi
}

function run_step {
    local name="$1"
    local script="$2"

    if grep -qx "$name" "$STATE_FILE" 2>/dev/null; then
        echo "[SKIP] $name"
        STEPS_SKIP+=("$name")
        return
    fi

    echo "[RUN]  $name..."
    if (bash "$script" >> "$LOG_FILE" 2>&1); then
        echo "$name" >> "$STATE_FILE"
        echo "[OK]   $name"
        STEPS_OK+=("$name")
    else
        echo "[FAIL] $name (see .install.log)"
        echo "$name" >> "$ERRORS_FILE"
        STEPS_FAIL+=("$name")
    fi
}

function fix_system {
    echo "[SYS] Running apt update..."
    sudo apt update && sudo apt full-upgrade -y

    echo "[SYS] Installing stow..."
    install_pkg stow

    echo "[SYS] Applying stow symlinks..."
    [ -f ~/.bashrc ] && [ ! -f ~/.bashrc.bk ] && mv ~/.bashrc ~/.bashrc.bk
    stow --adopt . && git -C "$DOTFILES_DIR" checkout .
}

function install_base {
    echo "[BASE] Installing base packages..."
    for pkg in chrome-gnome-shell curl git htop tree vim wget tmux zsh nvtop ibus-unikey; do
        install_pkg "$pkg"
    done
    chsh -s /usr/bin/zsh
}

function print_summary {
    local fail_count=${#STEPS_FAIL[@]}
    echo ""
    echo "=========================================="
    echo "  Install Summary"
    echo "=========================================="
    for s in "${STEPS_OK[@]+"${STEPS_OK[@]}"}";   do echo "  [OK]   $s"; done
    for s in "${STEPS_SKIP[@]+"${STEPS_SKIP[@]}"}"; do echo "  [SKIP] $s"; done
    for s in "${STEPS_FAIL[@]+"${STEPS_FAIL[@]}"}"; do echo "  [FAIL] $s"; done
    echo "=========================================="
    if [ "$fail_count" -gt 0 ]; then
        echo "  $fail_count failed. Check $LOG_FILE"
        echo "=========================================="
        return 1
    else
        echo "  All steps completed successfully."
        echo "=========================================="
    fi
}

# --- Main (only runs when executed directly, not sourced) ---

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Current working directory is: $(pwd)"

    # Clear errors file; append run separator to log
    > "$ERRORS_FILE"
    echo "" >> "$LOG_FILE"
    echo "=== Install run: $(date) ===" >> "$LOG_FILE"

    fix_system
    install_base

    chmod u+x "$DOTFILES_DIR"/scripts/programs/*.sh
    for script in "$DOTFILES_DIR"/scripts/programs/*.sh; do
        name="$(basename "$script" .sh)"
        run_step "$name" "$script"
    done

    sudo apt upgrade -y
    sudo apt autoremove -y

    print_summary
fi
```

- [ ] **Step 2: Run the tests and verify they pass**

```bash
bash scripts/test_orchestrator.sh
```

Expected output:
```
=== Test: successful step is recorded in state file ===
  PASS: state file contains test_ok
  PASS: errors file does not contain test_ok
  PASS: STEPS_OK has test_ok

=== Test: already-completed step is skipped ===
  PASS: STEPS_SKIP has test_ok
  PASS: STEPS_OK is empty

=== Test: failing step is recorded in errors file ===
  PASS: errors file contains test_fail
  PASS: state file does not contain test_fail
  PASS: STEPS_FAIL has test_fail

=== Test: failure in one step does not abort subsequent steps ===
  PASS: state file contains test_abort_check after prior failure

=== Test: exit inside script does not kill orchestrator ===
  PASS: orchestrator still running after exit 42

==========================================
  Test Results: 10 passed, 0 failed
==========================================
```

- [ ] **Step 3: Commit**

```bash
git add scripts/install.sh
git commit -m "feat: rewrite install.sh as resilient state-tracked orchestrator"
```

---

### Task 4: Verify idempotency fixes manually

**Files:**
- No changes — verify existing behavior

These checks require a live system (sudo), so they are manual. Run each and confirm no error is produced.

- [ ] **Step 1: Verify bashrc backup is idempotent**

```bash
# Simulate: backup already exists
touch /tmp/test_bashrc_src
cp /tmp/test_bashrc_src /tmp/test_bashrc_bk

# Source the condition inline
BASHRC=/tmp/test_bashrc_src
BASHRC_BK=/tmp/test_bashrc_bk
[ -f "$BASHRC" ] && [ ! -f "$BASHRC_BK" ] && mv "$BASHRC" "$BASHRC_BK" || echo "backup already exists, skipping (correct)"
```

Expected output: `backup already exists, skipping (correct)`

- [ ] **Step 2: Verify stow --adopt behavior**

```bash
# Dry run to check stow --adopt won't error on the current system
stow --adopt --no . 2>&1 | head -20
```

Expected: stow reports what it would do, no fatal errors.

- [ ] **Step 3: Commit if any tweaks were needed**

```bash
git add scripts/install.sh
git commit -m "fix: adjust idempotency edge cases found during manual verification"
```

(Skip this step if no changes were needed.)

---

### Task 5: Final cleanup and verification

**Files:**
- Modify: `scripts/install.sh` (if any fixes from Task 4)

- [ ] **Step 1: Run the full test suite one final time**

```bash
bash scripts/test_orchestrator.sh
```

Expected: `10 passed, 0 failed`

- [ ] **Step 2: Verify the script is syntactically valid**

```bash
bash -n scripts/install.sh && echo "Syntax OK"
bash -n scripts/test_orchestrator.sh && echo "Syntax OK"
```

Expected: `Syntax OK` for both.

- [ ] **Step 3: Final commit**

```bash
git add scripts/install.sh scripts/test_orchestrator.sh .gitignore
git status
git commit -m "feat: resilient install orchestrator with state tracking and error isolation"
```
