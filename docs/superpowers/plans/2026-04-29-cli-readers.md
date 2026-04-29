# CLI Readers (glow + bat) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `glow` (terminal markdown renderer) and `bat` (syntax-highlighted `cat` replacement) as managed dotfiles programs, including a `bat=batcat` alias in `.zshrc` and a user guide modeled on `docs/guides/nvim.md`.

**Architecture:** Single bundled install script (`scripts/programs/glow.sh`) installs `glow` via snap and `bat` via apt with independent idempotency guards. A one-line alias in `.zshrc` resolves Ubuntu's `batcat` binary to `bat`. A user guide at `docs/guides/cli-readers.md` documents both tools. Tests follow the existing skip-only idempotency pattern used by `docker.sh` / `visual_code.sh`.

**Tech Stack:** bash, GNU Stow, snap (for glow), apt (for bat).

**Spec:** `docs/superpowers/specs/2026-04-29-cli-readers-design.md`

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `scripts/programs/glow.sh` | Create | Idempotent installer for glow (snap) + bat (apt) |
| `.zshrc` | Modify | Append `alias bat=batcat` after KUBECONFIG export |
| `scripts/test_programs.sh` | Modify | Add two skip-when-installed test blocks (insertion point: between visual_code and terminator blocks, currently line 176) |
| `docs/guides/cli-readers.md` | Create | User guide for both tools, modeled on `docs/guides/nvim.md` |

No files deleted. No existing scripts modified.

---

## Pre-flight

- [ ] **Step 0.1: Confirm branch and tree state**

Run:
```bash
git status
git rev-parse --abbrev-ref HEAD
git log --oneline -2
```

Expected:
- Branch: `feat/cli-readers`
- HEAD commit: `docs: add design spec for CLI markdown readers (glow + bat)` (or similar — the spec commit at SHA starting `31316f1`)
- Working tree clean.

If on a different branch or the tree isn't clean, stop and ask.

- [ ] **Step 0.2: Confirm test suite is green**

Run:
```bash
bash scripts/test_programs.sh
```

Expected: ends with `Test Results: N passed, 0 failed`. As of writing, N = 35. Record the actual N you observe — you'll compare after Task 1.

---

## Task 1: Add `scripts/programs/glow.sh` (TDD)

**Files:**
- Modify: `scripts/test_programs.sh` (insert two new test blocks at line 176, immediately after `visual_code.sh` skip block, immediately before `terminator.sh` block)
- Create: `scripts/programs/glow.sh`

Tests first, confirm fail, then create the script, confirm pass.

- [ ] **Step 1.1: Insert two new test blocks in `scripts/test_programs.sh`**

Find the existing `visual_code.sh: skip when code already in PATH` block (currently lines 168–175). Append the following **immediately after** the line `assert_output_contains "visual_code.sh prints 'Already installed'" "Already installed" "$output"` (currently line 175) and **before** the blank line that precedes `# --- terminator.sh: ...` (currently line 177):

```bash

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
assert_output_contains "glow.sh prints 'Already installed: bat'" "Already installed: bat" "$output"
rm -f "$BIN_DIR/glow" "$BIN_DIR/batcat"
```

- [ ] **Step 1.2: Run the test suite to confirm new assertions FAIL**

Run:
```bash
bash scripts/test_programs.sh
```

Expected: the new assertions fail because `scripts/programs/glow.sh` does not yet exist (each `bash glow.sh` errors with "No such file or directory"). The syntax-check loop is unaffected (it only iterates over existing scripts). Older tests continue to pass. Final summary shows 5 new failures.

- [ ] **Step 1.3: Create `scripts/programs/glow.sh`**

Write the following exact content to `scripts/programs/glow.sh`:

```bash
#!/bin/bash
set -euo pipefail

# glow — terminal markdown renderer (snap, classic confinement)
if ! command -v glow &>/dev/null; then
    echo "Installing glow..."
    sudo snap install glow
else
    echo "Already installed: glow"
fi

# bat — syntax-highlighted cat (Ubuntu ships the binary as `batcat` due to a
# name conflict with bacula-console-qt; the `bat` alias is wired in .zshrc)
if ! command -v batcat &>/dev/null; then
    echo "Installing bat..."
    sudo apt-get install -y bat
else
    echo "Already installed: bat"
fi
```

Then make it executable:
```bash
chmod +x scripts/programs/glow.sh
```

- [ ] **Step 1.4: Run the test suite — all tests must now PASS**

Run:
```bash
bash scripts/test_programs.sh
```

Expected: ends with `Test Results: M passed, 0 failed` where M = N + 6 (5 new assertions + 1 from the syntax-check loop now picking up `glow.sh`). If anything fails, fix the script (do not modify the tests) and re-run.

- [ ] **Step 1.5: Commit**

```bash
git add scripts/test_programs.sh scripts/programs/glow.sh
git commit -m "feat(cli-readers): add idempotent install script for glow + bat"
```

---

## Task 2: Add `bat=batcat` alias to `.zshrc`

**Files:**
- Modify: `.zshrc` (append at end of file)

Ubuntu names the bat binary `batcat` because of a conflict with `bacula-console-qt`. The alias resolves the canonical name.

- [ ] **Step 2.1: Append the alias to `.zshrc`**

The `.zshrc` currently ends with the K3s kubectl config block (last non-blank line: `export KUBECONFIG=~/.kube/config`). Use Edit to append:

**old_string** (the exact final non-blank lines of the file):
```
# K3s kubectl config
export KUBECONFIG=~/.kube/config
```

**new_string:**
```
# K3s kubectl config
export KUBECONFIG=~/.kube/config

# Ubuntu names the bat binary `batcat` (conflicts with bacula-console-qt)
alias bat=batcat
```

- [ ] **Step 2.2: Verify the diff**

Run:
```bash
git diff .zshrc
```

Expected: the diff shows exactly 3 lines added (one blank line, one comment line, one alias line). No other lines change.

- [ ] **Step 2.3: Commit**

```bash
git add .zshrc
git commit -m "feat(zsh): alias bat=batcat for Ubuntu's renamed binary"
```

---

## Task 3: Write user guide `docs/guides/cli-readers.md`

**Files:**
- Create: `docs/guides/cli-readers.md`

Modeled on `docs/guides/nvim.md`. Reference that file's structure (sections: install/launch, mental model, key commands, workflows, troubleshooting) for tone and depth.

- [ ] **Step 3.1: Create the guide**

Write the following exact content to `docs/guides/cli-readers.md`:

````markdown
# CLI Readers — `glow` + `bat`

Reference for reading rendered markdown and syntax-highlighted source in the terminal. Both tools are installed by `scripts/programs/glow.sh`.

---

## What's installed

- **`glow`** (snap) — terminal markdown renderer. Beautiful headings/lists/tables/code-blocks, built-in pager, multiple themes. Best fit for prose, READMEs, and `.md` docs.
- **`bat`** (apt; binary is `batcat`, aliased to `bat` in `.zshrc`) — `cat` clone with syntax highlighting and Git integration. Best fit for source files, configs, JSON, logs.

Both work cleanly inside tmux (true color is configured in `.tmux.conf`). They do not depend on terminal image protocols, so rendering stays correct under tmux multiplexing.

---

## `glow` quick-start

```bash
glow                              # interactive TUI: pick a file in cwd
glow README.md                    # render and auto-page
glow -p file.md                   # force pager mode (always pages)
glow -s dark file.md              # theme: dark / light / auto / dracula / pink / notty
glow https://example.com/x.md     # render a URL directly
glow -                            # render stdin (e.g. `cat README.md | glow -`)
```

Inside the pager (powered by `less`):

| Key | Action |
|---|---|
| `j` / `k` or `↓` / `↑` | scroll one line |
| `Space` / `b` | scroll one page down / up |
| `g` / `G` | jump to top / bottom |
| `/pattern` | search forward; `n` / `N` to repeat |
| `q` | quit |

Inside the TUI (no args):

| Key | Action |
|---|---|
| `↑` / `↓` | move selection |
| `Enter` | open the selected file |
| `s` | stash a file (server mode — usually skip) |
| `q` / `Esc` | quit |

---

## `bat` quick-start

```bash
bat file.py                       # syntax-highlighted, line numbers, paged
bat -p file.py                    # plain mode: no decorations, no headers (pipe-friendly)
bat -A config.txt                 # show non-printable chars
bat -l json file.txt              # force JSON highlighting
bat -n script.sh                  # show line numbers only
bat file1.py file2.py             # concatenate multiple files
bat *.md                          # glob expansion works
diff a.json b.json | bat -l diff  # pipe diff output through bat with diff highlighting
```

Bat respects `$BAT_THEME` for the color scheme. Run `bat --list-themes` to see all options. Common picks: `Dracula`, `Monokai Extended`, `OneHalfDark`, `gruvbox-dark`. Set in `.zshrc`:

```bash
export BAT_THEME="OneHalfDark"
```

Bat auto-pages with `less` when output exceeds a screen. Pass `--paging=never` (or `bat -p`) for stdin-piping use.

---

## Tmux notes

- True-color works because `.tmux.conf` already sets `terminal-overrides ",xterm*:Tc"` and `default-terminal "screen-256color"`.
- Image protocols (Kitty graphics, sixel) are NOT used by either tool, so tmux multiplexing causes no rendering issues.
- Mouse-scroll inside the pager works if your tmux has `set -g mouse on` (it does).

---

## Common workflows

**"Read this project's README"**
```bash
glow README.md
```

**"Skim a JSON config"**
```bash
bat config.json                   # paged with highlighting
jq . config.json | bat -l json    # piped through jq for pretty-printing first
```

**"Compare two configs"**
```bash
diff -u old.yaml new.yaml | bat -l diff
```

**"Browse all markdown files in this repo"**
```bash
glow                              # TUI in cwd; navigate to .md files
```

**"Read a long log paged with grep"**
```bash
grep -n ERROR app.log | bat -l log
```

**"View `.zshrc` with line numbers"**
```bash
bat ~/.zshrc                      # alias resolves to batcat
```

**"Pipe arbitrary output through highlighting"**
```bash
echo '{"x":1}' | bat -l json -p
```

---

## Discovering more

```bash
glow --help
bat --help
bat --list-languages              # all supported syntaxes
bat --list-themes                 # all color schemes
```

---

## Troubleshooting

| Symptom | First thing to try |
|---|---|
| `bat: command not found` | Open a new terminal — the alias only loads on shell startup. Or `source ~/.zshrc`. |
| `glow: command not found` after install | New shell needed for snap binaries; or `hash -r` then retry. |
| Glow renders blank / wrong colors under tmux | Confirm `echo $TERM` is `screen-256color` inside tmux and `xterm-256color` outside. Confirm `.tmux.conf` has the `Tc` override. |
| `bat` paging is annoying for piping | Use `bat -p` (plain) or `bat --paging=never`. |
| Wrong theme | `bat --list-themes` then `export BAT_THEME="..."` in `.zshrc`. |
| Snap install of glow stalls | Snap is fetching from the snap store — wait. If permanently stuck, fall back to the apt repo install (`https://repo.charm.sh/apt/`). |

---

## Why these two

- **`glow` over `mdcat`** — mdcat tries to inline images via Kitty/iTerm graphics protocols, which break inside tmux. Glow doesn't render images, only text — safer in tmux.
- **`glow` over `frogmouth`** — Frogmouth is a TUI browser. Heavier startup, more for "read and navigate" sessions. Glow is faster for "open and read".
- **`bat` over `cat`** — `cat` has zero awareness of file structure. `bat` shows line numbers, syntax-highlights ~150 languages, and reuses `less` for paging. The plain mode (`bat -p`) is a drop-in replacement for `cat | less`.
````

- [ ] **Step 3.2: Commit**

```bash
git add docs/guides/cli-readers.md
git commit -m "docs: add user guide for glow + bat CLI readers"
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

Expected:
- `test_programs.sh` → `0 failed`, total = N + 6 (where N is the baseline pass count from Step 0.2).
- `test_orchestrator.sh` → `0 failed`.

- [ ] **Step 4.2: Confirm branch state**

Run:
```bash
git status
git log --oneline main..HEAD
```

Expected (oldest at bottom, newest on top):
- Working tree clean.
- 4 commits ahead of `main`:
  1. `docs: add user guide for glow + bat CLI readers`
  2. `feat(zsh): alias bat=batcat for Ubuntu's renamed binary`
  3. `feat(cli-readers): add idempotent install script for glow + bat`
  4. `docs: add design spec for CLI markdown readers (glow + bat)`

- [ ] **Step 4.3: Manual smoke instructions (for the user, post-merge)**

Print these instructions for the user — they cannot run inside CI:

```
MANUAL SMOKE TEST (run on the user's machine after merging to main):

1. Install:
   bash scripts/programs/glow.sh

2. Re-run to confirm idempotency:
   bash scripts/programs/glow.sh
   Expect: "Already installed: glow" and "Already installed: bat"

3. Open a NEW terminal so the alias loads:
   bat --version          # should print bat version (alias-resolved)
   glow --version         # should print glow version

4. Render a markdown file:
   glow ~/docs/guides/nvim.md

5. Syntax-highlight a config:
   bat ~/.zshrc

6. Inside tmux, repeat 4 and 5 — output should look identical.
```

- [ ] **Step 4.4: Hand off**

Stop here. Do not push or open a PR — the user runs that step (`git push -u origin feat/cli-readers` then `gh pr create`).
