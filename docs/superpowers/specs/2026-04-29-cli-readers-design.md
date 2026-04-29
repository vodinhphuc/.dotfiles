# CLI Readers (glow + bat) — Design

**Date:** 2026-04-29
**Scope:** Add `glow` (terminal markdown renderer) and `bat` (syntax-highlighted `cat` replacement) as managed dotfiles programs, with a user guide. Single feature, single PR.

## Goal

After running `bash scripts/install.sh` on a fresh Ubuntu machine and applying stow, the user can:

- Run `glow path/to/file.md` to read rendered markdown in the terminal (works under tmux with full color).
- Run `bat path/to/file` to view any file with syntax highlighting and paging (the `bat` alias resolves to Ubuntu's `batcat` binary).

Plus an indexed user guide at `docs/guides/cli-readers.md` modeled on `docs/guides/nvim.md`.

## Decisions

1. **Single install script bundling both tools.** Bundle in `scripts/programs/glow.sh` because the user's intent is a single feature ("read markdown / source nicely in the terminal"), and the existing repo already has a precedent for bundling in one script: `custome_zsh.sh` installs four related zsh components. Bundling avoids creating two trivial single-line scripts.
2. **Install method per tool:**
   - `glow` via `sudo snap install glow` (classic confinement → full filesystem access). Matches `docker.sh` / `visual_code.sh` snap pattern. Auto-updates via snap.
   - `bat` via `sudo apt-get install -y bat`. Ubuntu ships the binary as `batcat` due to a name conflict with `bacula-console-qt`; both `command -v batcat` and `dpkg -l | grep bat` are valid idempotency checks. We use `command -v batcat` for parity with `docker`/`code`/`nvim` scripts.
3. **`bat=batcat` alias in `.zshrc`** (not `.bashrc`). `.zshrc` is the user's actual interactive shell; `.bashrc` is the rarely-used secondary. Adding to `.bashrc` is YAGNI.
4. **Testing scope: idempotency-skip only.** The existing test_programs.sh has two patterns: skip-only (most scripts) and skip + install-flow (terminator, neovim). For this small bundle, skip-only matches the precedent set by `docker.sh` and `visual_code.sh`. The neovim install-flow test was thorough enough to cover the apt+sudo mocking pattern; replicating it for glow/bat would be redundant boilerplate.
5. **User guide naming: `cli-readers.md`.** `glow.md` would mislead since the guide also covers `bat`; `markdown-reader.md` would mislead since `bat` isn't markdown-specific. `cli-readers` is accurate.

## Components

### `scripts/programs/glow.sh` (new)

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

Two independent idempotency guards so re-running after a partial install picks up the missing tool without redoing the installed one.

### `.zshrc` (modify)

Append the alias to the existing export block at the bottom of the file (currently ends with `export KUBECONFIG=~/.kube/config`):

```bash
alias bat=batcat
```

Final state of the appended block:

```bash
export PATH=~/.npm-global/bin:$PATH

# K3s kubectl config
export KUBECONFIG=~/.kube/config

# Ubuntu names the bat binary `batcat` (conflicts with bacula-console-qt)
alias bat=batcat
```

### `scripts/test_programs.sh` (modify)

Insert two new test blocks following the same shape as the existing `docker.sh` / `visual_code.sh` skip tests. Insertion point: after the existing `visual_code.sh` block (currently ends around line 132), before the terminator block.

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

# --- glow.sh: skip when batcat already in PATH (glow path is independently exercised) ---
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

The two blocks overlap in coverage but cement the behavior of each guard independently. Total new assertions: 5 (3 in the first block + 2 in the second). The script is also picked up by the existing syntax-check loop, contributing 1 additional assertion.

### `docs/guides/cli-readers.md` (new)

Structure (mirroring `docs/guides/nvim.md`):

1. **What's installed** — one-paragraph each on glow and bat
2. **`glow` quick-start** — TUI mode, file mode, `-p` (force pager), pager keybinds, theme flags
3. **`bat` quick-start** — basic replacement for `cat`, line numbers, themes, language override (`-l`)
4. **Tmux notes** — why glow over mdcat (image protocols), confirmation that true color is fine
5. **Common workflows** — "read a project README", "skim a JSON config", "compare two configs (`bat -p`)", "view a long log paged with grep"
6. **Troubleshooting** — `bat: command not found` → restart shell; glow snap and confinement; `batcat -p` no decorations; etc.

## Data flow / first-run UX

```
bash scripts/install.sh
  → run_step "glow" scripts/programs/glow.sh
    → snap install glow                      (~30s)
    → apt-get install -y bat                 (~5s)
  → other programs continue
  → stow .                                    (re-applies symlinks; .zshrc alias active in new shells)

User opens a new terminal:
  glow ~/docs/guides/nvim.md                 # rendered markdown
  bat ~/.zshrc                                # syntax-highlighted shell config
```

## Error handling

- `set -euo pipefail` aborts on any apt/snap failure; orchestrator records the failure in `.install_errors`.
- Idempotency guards prevent reinstall on `install.sh` re-runs.
- `set -e` aborts on the first install failure, so a `snap install glow` failure prevents the subsequent `apt install bat`. This matches the orchestrator's expectation: record one failure in `.install_errors`, user re-runs `install.sh`, the working install is detected as already-present, and the failed install is retried. Partial state is recoverable on re-run.
- If snap is unavailable on the system (extremely unlikely on Ubuntu Desktop), the script fails loudly. We do not pre-check for snap because every existing snap-using script in this repo also assumes it.

## Testing

### Automated

`scripts/test_programs.sh` adds the two idempotency-skip blocks described above. Mocks `glow` and `batcat` via the existing `$BIN_DIR` PATH-prepend pattern. No network, no sudo.

### Manual verification (post-install)

1. `bash scripts/programs/glow.sh` — expect `Installing glow...` + `Installing bat...` (or `Already installed: …` if pre-existing).
2. `bash scripts/programs/glow.sh` — second run expects `Already installed: glow` and `Already installed: bat`.
3. Open a new terminal, run `glow docs/guides/nvim.md` — expect rendered markdown with paging.
4. Run `bat .zshrc` (uses the alias) — expect syntax-highlighted output with line numbers.
5. Inside tmux, repeat steps 3–4 — expect identical rendering, no escape-sequence garbage.

## Out of scope

- `mdcat`, `frogmouth`, or other markdown alternatives — `glow` is the chosen tool.
- `bash` alias for `bat=batcat` in `.bashrc` — the user does not actively use bash; YAGNI until they ask.
- Configuring `PAGER`, `BAT_THEME`, or `GLOW_STYLE` env vars — defaults are fine; user can tweak later.
- Replacing `less` / `cat` / `man` system-wide via aliases — too invasive; the user can opt in piecemeal from the guide.
- Adding `ripgrep`/`fd` install (already pulled in by `neovim.sh`).
