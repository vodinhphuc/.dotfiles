# Tmux Config Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the broken `@plugins` directives in `.tmux.conf` and have `scripts/programs/tpm.sh` auto-install plugins so `bash scripts/install.sh` produces a fully working tmux setup with no manual `prefix + I` step.

**Architecture:** Two surgical changes — (1) correct typos and drop the half-broken `vim-tmux-navigator` line in `.tmux.conf`, (2) extend `tpm.sh` to invoke TPM's idempotent `install_plugins` helper after cloning. A new test in `test_programs.sh` proves the install_plugins call happens. No new files, no architecture shift.

**Tech Stack:** bash, GNU Stow, Tmux Plugin Manager (TPM).

**Spec:** `docs/superpowers/specs/2026-04-27-tmux-config-fix-design.md`

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `.tmux.conf` | Modify | Plugin declarations corrected; vim-tmux-navigator removed |
| `scripts/programs/tpm.sh` | Modify | Adds idempotent `install_plugins` invocation after clone |
| `scripts/test_programs.sh` | Modify | Adds test asserting `install_plugins` is invoked when present |

No files created. No files deleted.

---

## Pre-flight

- [ ] **Step 0.1: Confirm clean working tree for files we plan to touch**

Run:
```bash
git status -- .tmux.conf scripts/programs/tpm.sh scripts/test_programs.sh
```

Expected: all three listed as unchanged. (`.bashrc` / `.zshrc` are unrelated user changes — leave them alone.)

If `.tmux.conf.swp` exists, ask the user to close their vim session on `.tmux.conf` before proceeding. Do not delete the swap file.

- [ ] **Step 0.2: Confirm current test suite passes**

Run:
```bash
bash scripts/test_programs.sh
```

Expected: ends with `Test Results: N passed, 0 failed`. Record N.

---

## Task 1: Add failing test for `install_plugins` invocation

**Files:**
- Modify: `scripts/test_programs.sh` (insert a new test block after line 95, before the miniconda block)

We'll add a test that creates a TPM dir containing a fake `bin/install_plugins` script which writes a sentinel file when invoked. After running `tpm.sh`, the sentinel must exist.

- [ ] **Step 1.1: Insert new test block in `scripts/test_programs.sh`**

Find the existing tpm block (lines 87–95):

```bash
# --- tpm.sh: skip when TPM dir exists ---
echo ""
echo "=== tpm.sh: skip when already installed ==="
MOCK_HOME="$TEST_DIR/home_tpm"
mkdir -p "$MOCK_HOME/.tmux/plugins/tpm"
output=$(HOME="$MOCK_HOME" bash "$DOTFILES_DIR/scripts/programs/tpm.sh" 2>&1)
code=$?
assert_exit_zero "tpm.sh exits 0 when already installed" "$code"
assert_output_contains "tpm.sh prints 'Already installed'" "Already installed" "$output"
```

Append immediately after it (before the miniconda block on line 97):

```bash
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
```

- [ ] **Step 1.2: Run the test suite to confirm the new assertions FAIL**

Run:
```bash
bash scripts/test_programs.sh
```

Expected: the two new assertions fail (`tpm.sh invokes install_plugins` and `tpm.sh announces plugin install`). Old tests continue to pass. Final summary shows `2 failed`.

- [ ] **Step 1.3: Commit the failing test**

```bash
git add scripts/test_programs.sh
git commit -m "test: assert tpm.sh invokes install_plugins after clone"
```

---

## Task 2: Make `tpm.sh` invoke `install_plugins`

**Files:**
- Modify: `scripts/programs/tpm.sh` (append a new block after the existing `if/else/fi`)

- [ ] **Step 2.1: Update `scripts/programs/tpm.sh`**

Replace the entire file contents with:

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

# Install/update plugins listed in ~/.tmux.conf (idempotent).
# install_plugins is provided by TPM and is a no-op for already-installed plugins.
if [ -x "$TPM_DIR/bin/install_plugins" ]; then
    echo "Installing tmux plugins from .tmux.conf..."
    "$TPM_DIR/bin/install_plugins"
fi
```

- [ ] **Step 2.2: Run the test suite — all tests must now PASS**

Run:
```bash
bash scripts/test_programs.sh
```

Expected: `Test Results: M passed, 0 failed` where M = N + 3 (the three new assertions from Task 1 now pass).

- [ ] **Step 2.3: Commit**

```bash
git add scripts/programs/tpm.sh
git commit -m "feat(tpm): auto-install tmux plugins after cloning TPM"
```

---

## Task 3: Fix typos in `.tmux.conf`

No automated test covers this file (it's a tmux config, not a script). The TDD loop happens via the manual smoke test in Task 4.

**Files:**
- Modify: `.tmux.conf` (lines 29, 40, 41, 42)

- [ ] **Step 3.1: Apply four edits to `.tmux.conf`**

Edit 1 — line 29:
- Old: `set -g @plugins 'tmux/plugins/tmux-yank'`
- New: `set -g @plugin 'tmux-plugins/tmux-yank'`

Edit 2 — delete line 40 entirely:
- Old: `set -g @plugins 'tmux-plugins/tpm'`
- New: *(line removed)*

Edit 3 — line 41 (becomes line 40 after the delete above):
- Old: `set -g @plugins 'tmux-plugins/tmux/sensible'`
- New: `set -g @plugin 'tmux-plugins/tmux-sensible'`

Edit 4 — delete the vim-tmux-navigator line:
- Old: `set -g @plugins 'christoomey/vim-tmux-navigator'`
- New: *(line removed)*

- [ ] **Step 3.2: Confirm only those four lines changed**

Run:
```bash
git diff .tmux.conf
```

Expected diff structure:
- Line 29 changed (`@plugins` → `@plugin`, path corrected).
- Three lines removed (old line 40 tpm, old line 41 sensible old form replaced not removed, old line 42 vim-tmux-navigator).
- Net: 1 line modified, 1 line modified, 2 lines deleted. No other changes.

- [ ] **Step 3.3: Re-run syntax check loop in test suite**

The test suite's syntax-check loop only covers `scripts/programs/*.sh`, not `.tmux.conf`. Validate `.tmux.conf` instead by sourcing it in a tmux server:

```bash
tmux kill-server 2>/dev/null || true
tmux new-session -d -s plan_smoke
tmux source-file ~/.tmux.conf
echo $?
tmux kill-session -t plan_smoke
```

Expected: `0` printed; no error output. (Skip this step if tmux is not currently running on this machine and starting it would interfere with active work — note the skip.)

- [ ] **Step 3.4: Commit**

```bash
git add .tmux.conf
git commit -m "fix(tmux): correct @plugins typos and drop unused vim-tmux-navigator"
```

---

## Task 4: Manual smoke test

**Files:** none modified.

This is the only check that the *runtime* behavior is correct — automated tests cover the script wiring, but the actual tmux UX needs eyeballs.

- [ ] **Step 4.1: Re-run TPM install with new config**

```bash
bash scripts/programs/tpm.sh
```

Expected output contains both:
- `Already installed: <path>` (TPM dir still present from before)
- `Installing tmux plugins from .tmux.conf...`

No errors. The tmux-yank and tmux-sensible plugin directories should now exist:

```bash
ls ~/.tmux/plugins/
```

Expected: at least `tpm`, `tmux`, `tmux-yank`, `tmux-sensible` directories. (`tmux` is catppuccin's repo name.)

- [ ] **Step 4.2: Verify catppuccin still loads (regression check)**

Open tmux. Status bar shows the catppuccin mocha purple/pink theme. If it doesn't, something regressed — investigate before proceeding.

- [ ] **Step 4.3: Verify tmux-yank works**

In a tmux pane:
1. Press `prefix` (`Ctrl+Space`), then `[` to enter copy-mode.
2. Press `v` to start selection, move cursor with `h/j/k/l`, press `y`.
3. Switch to a browser or VS Code, press `Ctrl+V`.

Expected: the selected text appears. If `xclip` or `xsel` is missing, install it (`sudo apt-get install -y xclip`) — tmux-yank requires one of them.

- [ ] **Step 4.4: Verify tmux-sensible loaded**

In a tmux pane:
1. Press `prefix`, then `R`.

Expected: status bar briefly shows `Reloaded!` (this binding comes from tmux-sensible).

- [ ] **Step 4.5: If any verification step failed, do not commit anything new**

Roll back by running `git status` to identify any uncommitted changes; reopen the relevant Task and fix. The commits from Tasks 1–3 stay regardless — they are correct independent of plugin runtime behavior.

---

## Task 5: Wrap-up

- [ ] **Step 5.1: Confirm git history is clean and tests pass**

```bash
git log --oneline -5
bash scripts/test_programs.sh
```

Expected: three new commits in order — test, feat, fix. Test suite shows 0 failed.

- [ ] **Step 5.2: Report completion**

Summarize to the user:
- Three commits added.
- Plugins now actually load on a fresh install.
- vim-tmux-navigator was intentionally dropped; can be re-added once a vim plugin manager is set up.

No further commits or pushes — `git push` is the user's call.

---

## Self-review notes

- **Spec coverage:** All decisions in the spec map to tasks: typo fixes (Task 3), drop vim-tmux-navigator (Task 3), drop `tmux-plugins/tpm` line (Task 3), auto-install via tpm.sh (Task 2), test coverage (Task 1), manual verification (Task 4). ✅
- **Placeholder scan:** No TBDs, no "handle errors appropriately", no "similar to". Every code change shows the full new content. ✅
- **Type consistency:** Variable names (`TPM_DIR`, `MOCK_HOME`, `SENTINEL`, `TPM_BIN`) used consistently across tasks. Test description strings quoted exactly as they appear in `assert_*` calls. ✅
