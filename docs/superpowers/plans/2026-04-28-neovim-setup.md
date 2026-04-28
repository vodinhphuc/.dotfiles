# Neovim Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Neovim as a managed dotfiles program with a kickstart.nvim-based config that pre-configures LSP, Treesitter parsers, and formatters for Lua, Bash, Python, Go, and TypeScript. After `bash scripts/install.sh` + `stow .`, the user can launch `nvim` and get a working IDE-like editor with no manual setup.

**Architecture:** One new install script (`scripts/programs/neovim.sh`) and one new config file (`.config/nvim/init.lua`, vendored from upstream kickstart.nvim with three localized customizations). Config is stow-managed so it lives alongside `.tmux.conf`/`.zshrc`. Tests for the install script live in `scripts/test_programs.sh` and follow the existing PATH-prepended-mock pattern (no sudo, no network).

**Tech Stack:** bash, GNU Stow, Neovim 0.10+ (from `ppa:neovim-ppa/stable`), [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim), `lazy.nvim`, Mason (LSP installer), Treesitter, conform.nvim.

**Spec:** `docs/superpowers/specs/2026-04-28-neovim-setup-design.md`

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `scripts/programs/neovim.sh` | Create | Idempotent installer: adds Neovim PPA, installs `neovim` + tooling deps (ripgrep, fd-find, nodejs, etc.) |
| `.config/nvim/init.lua` | Create | Vendored kickstart.nvim init.lua with bash/python/go/ts LSPs, treesitter parsers, formatters |
| `scripts/test_programs.sh` | Modify | Adds two tests: idempotency-skip, and apt-call invocations |

No files deleted. No existing scripts modified.

---

## Pre-flight

- [ ] **Step 0.1: Confirm working branch and tree state**

Run:
```bash
git status
git rev-parse --abbrev-ref HEAD
```

Expected:
- Branch: `feat/neovim-setup`
- The spec commit (`docs: add design spec for neovim setup`) is on top of the branch (`git log --oneline -1`).
- `.bashrc` and `.zshrc` may show as modified — these are unrelated user changes; do not touch them.
- No staged files.

If on a different branch, stop and ask the user before proceeding.

- [ ] **Step 0.2: Confirm current test suite passes**

Run:
```bash
bash scripts/test_programs.sh
```

Expected: ends with `Test Results: N passed, 0 failed`. Record N (you'll compare to it after each task).

- [ ] **Step 0.3: Confirm `.config/nvim/` does not yet exist in the repo**

Run:
```bash
ls -la .config 2>&1 || echo "no .config dir — good"
```

Expected: directory does not exist (or is empty). If it does exist with content, stop and ask the user before proceeding — there may be unrelated config we should not clobber.

---

## Task 1: Add `scripts/programs/neovim.sh` (TDD)

**Files:**
- Modify: `scripts/test_programs.sh` (insert two new test blocks after the tpm-install_plugins block, before the miniconda block — currently line 114)
- Create: `scripts/programs/neovim.sh`

We add the failing tests first, confirm they fail, then create the script and confirm they pass.

- [ ] **Step 1.1: Insert two new test blocks in `scripts/test_programs.sh`**

Find the `# --- tpm.sh: invokes install_plugins when binary is present ---` block (currently lines 97–113). Append the following **immediately after** the closing `assert_output_contains "tpm.sh announces plugin install" ...` line (currently line 113) and **before** `# --- miniconda.sh: ...` (currently line 115):

```bash
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
output=$(PATH="$BIN_DIR" bash "$DOTFILES_DIR/scripts/programs/neovim.sh" 2>&1) || true
log_content="$(cat "$NEOVIM_LOG" 2>/dev/null)"
assert_output_contains "neovim.sh adds the neovim stable PPA" "ppa:neovim-ppa/stable" "$log_content"
assert_output_contains "neovim.sh installs the neovim package" "neovim" "$log_content"
assert_output_contains "neovim.sh installs ripgrep (Telescope dep)" "ripgrep" "$log_content"
assert_output_contains "neovim.sh installs fd-find (Telescope dep)" "fd-find" "$log_content"
assert_output_contains "neovim.sh installs nodejs (for Mason-managed LSPs)" "nodejs" "$log_content"
assert_output_contains "neovim.sh notes missing go toolchain" "Mason will skip gopls" "$output"
# Cleanup: remove the logging mocks so they don't affect later tests
rm -f "$BIN_DIR/apt-get" "$BIN_DIR/add-apt-repository" "$BIN_DIR/sudo"
```

- [ ] **Step 1.2: Run the test suite to confirm new assertions FAIL**

Run:
```bash
bash scripts/test_programs.sh
```

Expected: every new assertion fails because `scripts/programs/neovim.sh` does not exist (bash will error with "No such file or directory" on each run). The first new test block also fails on the syntax-check loop (script missing → no syntax check, but other tests still run). Older tests should still pass.

The summary line will show several new failures (around 7) plus the existing pass count from Step 0.2.

- [ ] **Step 1.3: Create `scripts/programs/neovim.sh`**

Write the following exact content to `scripts/programs/neovim.sh`:

```bash
#!/bin/bash
set -euo pipefail

if command -v nvim &>/dev/null; then
    echo "Already installed: neovim"
    exit 0
fi

echo "Adding Neovim stable PPA..."
sudo add-apt-repository -y ppa:neovim-ppa/stable
sudo apt-get update

echo "Installing Neovim and dependencies..."
sudo apt-get install -y \
    neovim \
    ripgrep \
    fd-find \
    git \
    build-essential \
    unzip \
    xclip \
    nodejs \
    npm

if ! command -v go &>/dev/null; then
    echo "Note: 'go' is not on PATH. Mason will skip gopls until Go is installed."
fi

echo "Neovim installation complete."
```

Then make it executable:
```bash
chmod +x scripts/programs/neovim.sh
```

- [ ] **Step 1.4: Run the test suite — all tests must now PASS**

Run:
```bash
bash scripts/test_programs.sh
```

Expected: ends with `Test Results: M passed, 0 failed` where M = N + 7 (the seven new assertions: 2 from the skip-test block + 6 from the install-test block). The syntax-check loop now also runs cleanly on the new `neovim.sh`.

If anything fails, fix the script (do **not** modify the tests) and re-run.

- [ ] **Step 1.5: Commit**

```bash
git add scripts/test_programs.sh scripts/programs/neovim.sh
git commit -m "feat(neovim): add idempotent neovim install script with tests"
```

---

## Task 2: Vendor kickstart.nvim `init.lua`

**Files:**
- Create: `.config/nvim/init.lua` (copied from upstream kickstart.nvim)

We bring in the upstream file unmodified first, so the customization commit (Task 3) shows a clean diff against pristine kickstart. This also lets the user `git log` to see exactly what we changed vs. upstream.

- [ ] **Step 2.1: Create `.config/nvim/` directory in the repo**

Run from repo root:
```bash
mkdir -p .config/nvim
```

- [ ] **Step 2.2: Clone kickstart.nvim to a temp dir and copy its `init.lua`**

Run:
```bash
TMP_DIR="$(mktemp -d)"
git clone --depth 1 https://github.com/nvim-lua/kickstart.nvim "$TMP_DIR"
cp "$TMP_DIR/init.lua" .config/nvim/init.lua
# Record the upstream commit hash for the commit message
UPSTREAM_SHA="$(git -C "$TMP_DIR" rev-parse HEAD)"
echo "Upstream kickstart.nvim SHA: $UPSTREAM_SHA"
rm -rf "$TMP_DIR"
```

Save the printed `$UPSTREAM_SHA` value — it goes in the commit message.

- [ ] **Step 2.3: Sanity-check the file**

Run:
```bash
wc -l .config/nvim/init.lua
head -5 .config/nvim/init.lua
grep -c "lua_ls" .config/nvim/init.lua
grep -c "ensure_installed" .config/nvim/init.lua
grep -c "formatters_by_ft" .config/nvim/init.lua
```

Expected:
- File is several hundred to ~1100 lines (upstream size varies).
- First few lines contain comments referencing kickstart.
- `lua_ls` appears at least once (LSP server table).
- `ensure_installed` appears at least once (Treesitter parser list).
- `formatters_by_ft` appears at least once (conform.nvim config).

If any of these greps return 0, kickstart's structure has shifted significantly — stop and ask the user before continuing. The customization edits in Task 3 rely on these anchors.

- [ ] **Step 2.4: Commit**

Replace `<sha>` below with the value from Step 2.2:

```bash
git add .config/nvim/init.lua
git commit -m "chore(nvim): vendor kickstart.nvim init.lua

Imported from https://github.com/nvim-lua/kickstart.nvim @ <sha>"
```

---

## Task 3: Customize `init.lua` for Bash, Python, Go, TypeScript

**Files:**
- Modify: `.config/nvim/init.lua` (four targeted edits — three customizations + a header comment)

All four edits land in a single commit so the diff against vendored upstream tells one story.

- [ ] **Step 3.1: Read `init.lua` to locate the three anchor regions**

Run these and read the surrounding context for each:
```bash
grep -n "lua_ls = {" .config/nvim/init.lua
grep -n "ensure_installed = {" .config/nvim/init.lua
grep -n "formatters_by_ft = {" .config/nvim/init.lua
```

Note the line numbers — you'll use them to find the exact `old_string` for each Edit operation.

- [ ] **Step 3.2: Add `bashls`, `pyright`, `gopls`, `ts_ls` to the LSP `servers` table**

Use the Edit tool. The anchor is the line `lua_ls = {`. We insert four new entries **immediately above** it.

Find the exact line in the file. It will look like (indentation: 4 spaces, since kickstart uses 4-space indent inside the `servers` table):

```lua
    lua_ls = {
```

Replace that single line with:

```lua
    bashls = {},
    pyright = {},
    gopls = {},
    ts_ls = {},

    lua_ls = {
```

Use Edit with `old_string` = `    lua_ls = {` and `new_string` = the 6-line block above. If `old_string` is not unique (it shouldn't be — `lua_ls = {` only appears once as a server declaration), Edit will succeed on the single match.

- [ ] **Step 3.3: Extend Treesitter `ensure_installed` to include python/go/typescript/tsx**

Find the `ensure_installed = { ... }` line for treesitter. Upstream typically looks like:

```lua
      ensure_installed = { 'bash', 'c', 'diff', 'html', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc' },
```

(Exact list may differ — read the actual line first.)

Use Edit to replace that single line with the same list plus our four additions appended before the closing `}`:

```lua
      ensure_installed = { 'bash', 'c', 'diff', 'html', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc', 'python', 'go', 'typescript', 'tsx' },
```

If upstream's list differs, preserve their entries exactly and only append `'python', 'go', 'typescript', 'tsx'` (skipping any already present — `bash` is typically there already; do **not** duplicate it).

- [ ] **Step 3.4: Extend `formatters_by_ft` for sh/python/go/typescript**

Find the `formatters_by_ft = {` line. The block typically looks like:

```lua
    formatters_by_ft = {
      lua = { 'stylua' },
      -- Conform can also run multiple formatters sequentially
      -- python = { "isort", "black" },
      --
      -- You can use 'stop_after_first' to run the first available formatter from the list
      -- javascript = { "prettierd", "prettier", stop_after_first = true },
    },
```

Use Edit to replace the whole block above with:

```lua
    formatters_by_ft = {
      lua = { 'stylua' },
      sh = { 'shfmt' },
      python = { 'isort', 'black' },
      go = { 'goimports', 'gofmt' },
      typescript = { 'prettier' },
      typescriptreact = { 'prettier' },
      javascript = { 'prettier' },
    },
```

If upstream's block content differs, preserve `lua = { 'stylua' },` (always present) and append our six new lines below it before the closing `},`.

- [ ] **Step 3.5: Add a header comment block at the top of `init.lua`**

Use Edit to prepend a header block. The existing first line of upstream kickstart is typically `--[[` (the start of a long comment block). Find the **exact first line** of the file (use Read with limit=1), then Edit to prepend:

```lua
-- ============================================================================
-- Vendored from https://github.com/nvim-lua/kickstart.nvim
--
-- LOCAL CUSTOMIZATIONS (search anchors):
--   1. LSP servers       — search:  bashls = {},
--   2. Treesitter parsers — search:  'python', 'go', 'typescript', 'tsx'
--   3. Formatters         — search:  sh = { 'shfmt' },
--
-- Learning entry points:
--   :Tutor       — interactive vim/nvim tutor
--   :checkhealth — diagnose plugin/LSP/treesitter status
--   :help        — built-in help (e.g. :help lazy.nvim)
-- ============================================================================

```

(Note the trailing blank line.) The Edit replaces the first line with the header block followed by that same first line — pure insertion.

- [ ] **Step 3.6: Local sanity check**

Run:
```bash
grep -c "bashls = {}" .config/nvim/init.lua            # expect: 1
grep -c "'python', 'go', 'typescript', 'tsx'" .config/nvim/init.lua  # expect: 1
grep -c "sh = { 'shfmt' }" .config/nvim/init.lua       # expect: 1
grep -c "Vendored from https://github.com/nvim-lua/kickstart.nvim" .config/nvim/init.lua  # expect: 1
```

If any of these is not exactly 1, re-do the corresponding edit. (0 = edit didn't apply; 2+ = the edit was applied twice or upstream had duplicates.)

- [ ] **Step 3.7: Verify Lua syntax is still valid**

If `nvim` is locally installed (it won't be on a fresh machine — that's fine, skip):

```bash
if command -v nvim &>/dev/null; then
    nvim --headless -u .config/nvim/init.lua "+qa" 2>&1 | head -20
    echo "exit: $?"
fi
```

Expected: exits 0 with no Lua syntax errors. (Plugin-resolution warnings during first launch are not a problem here; we're only checking that the file parses.)

If `nvim` is not installed, skip this step — the plan's manual verification (Task 4.2) will catch syntax errors on first real launch.

- [ ] **Step 3.8: Commit**

```bash
git add .config/nvim/init.lua
git commit -m "feat(nvim): customize kickstart with bash/python/go/ts LSPs and formatters

- Add bashls, pyright, gopls, ts_ls to LSP servers (Mason auto-installs)
- Add python, go, typescript, tsx Treesitter parsers
- Add shfmt, isort+black, goimports+gofmt, prettier formatters via conform
- Prepend header pointing at customization sites and learning resources"
```

---

## Task 4: Final verification

**Files:** none modified.

- [ ] **Step 4.1: Full automated suite**

Run:
```bash
bash scripts/test_programs.sh
bash scripts/test_orchestrator.sh
```

Expected: both end with `0 failed`. Record the new total pass count and confirm it is exactly N + 7 from Task 1 (no orchestrator changes were made).

- [ ] **Step 4.2: Manual smoke test (document for the user)**

This step cannot be automated — it requires actually installing Neovim on the user's machine. Print these instructions for the user:

```
MANUAL SMOKE TEST (run on the user's machine after merging):

1. Install Neovim and stow the config:
   bash scripts/programs/neovim.sh
   stow .

2. First launch — wait ~30s for lazy.nvim to install plugins:
   nvim
   (close with :qa once the dashboard appears)

3. Verify health:
   nvim '+checkhealth'
   - lazy, mason, treesitter, telescope should all be green.
   - gopls may show yellow if `go` is not installed (expected).

4. Open a file of each type and confirm:
   - Syntax highlighting (Treesitter)
   - LSP starts: hover with K, go-to-def with gd
   - Format: :Format (or :lua require('conform').format() depending on kickstart version)

   Try: a .sh file, .py file, .go file, .ts file.

5. Confirm Telescope:
   nvim, then <leader>sf (find files), <leader>sg (live grep)
```

- [ ] **Step 4.3: Confirm git tree is clean**

Run:
```bash
git status
git log --oneline -5
```

Expected:
- Working tree clean (except possibly the unrelated `.bashrc` / `.zshrc` modifications).
- Top three commits on `feat/neovim-setup` (newest first):
  1. `feat(nvim): customize kickstart with bash/python/go/ts LSPs and formatters`
  2. `chore(nvim): vendor kickstart.nvim init.lua`
  3. `feat(neovim): add idempotent neovim install script with tests`
- The spec commit (`docs: add design spec for neovim setup`) sits below those three.

- [ ] **Step 4.4: Hand off to the user for branch finalization**

Stop here. Do **not** push, open a PR, or merge — the user runs that step themselves following the same flow used for the tmux PR (push branch, open PR, review, merge, sync `main`, delete branch).
