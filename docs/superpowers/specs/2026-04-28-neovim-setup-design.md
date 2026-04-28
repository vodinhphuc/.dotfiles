# Neovim Setup — Design

**Date:** 2026-04-28
**Scope:** Add Neovim as a managed dotfiles program with a hand-rolled-style config based on kickstart.nvim, pre-configured for Lua, Bash, Python, Go, and TypeScript.

## Goal

After running `bash scripts/install.sh` on a fresh Ubuntu machine, the user can launch `nvim` and get a working IDE-like terminal editor with LSP, fuzzy finding, syntax highlighting, git integration, and autocomplete — with no manual setup steps. The configuration must be readable and learnable, not a black-box distro.

## Decisions

1. **Use kickstart.nvim as the base.** Single-file `init.lua` (~700 lines), heavily commented, maintained by a core Neovim developer. Designed explicitly as a teaching config that the user reads and modifies. Chosen over LazyVim/NvChad (too polished, hides internals) and from-scratch (too much boilerplate to write before reaching anything useful).
2. **Vendor the file, do not submodule.** Copy `init.lua` into the dotfiles repo and treat it as ours. Fits the "everything machine-setup lives here, versioned" philosophy. Upstream kickstart updates can be diffed and merged manually as a deliberate act when the user wants them.
3. **Stow-managed config.** Place the file at `.config/nvim/init.lua` in the repo root so the existing `stow .` step symlinks it to `~/.config/nvim/init.lua` with no extra orchestration.
4. **Install Neovim from the official PPA, not Ubuntu apt.** Ubuntu's apt nvim package lags far behind upstream; kickstart requires Neovim 0.10+. Use `ppa:neovim-ppa/stable` for a maintained recent stable release.
5. **Pre-configure five language servers in one edit.** Extend kickstart's `servers` table with `bashls`, `pyright`, `gopls`, `ts_ls` alongside the default `lua_ls`. Mason auto-installs them on first launch.
6. **Install Node.js as part of the Neovim program.** Three of the five LSPs (`bashls`, `pyright`, `ts_ls`) are npm-distributed and Mason needs `npm` on PATH. Bundling Node.js with the Neovim install removes a hidden prerequisite.
7. **Do not require Go.** `gopls` will be skipped by Mason if `go` is not on PATH. The install script logs a hint, but a missing Go toolchain is not a blocker for the rest of the editor working.

## Components

### `scripts/programs/neovim.sh` (new)

Idempotent install script following the existing `scripts/programs/*.sh` conventions.

Responsibilities:

1. Guard with `command -v nvim`. If present, print `Already installed: neovim` and exit 0.
2. Add `ppa:neovim-ppa/stable` via `add-apt-repository -y`.
3. Run `apt-get update`, then `apt-get install -y` for:
   - `neovim` — the editor
   - `ripgrep` — Telescope live-grep dependency
   - `fd-find` — Telescope file-find dependency
   - `git`, `build-essential`, `unzip` — Treesitter parser compilation
   - `xclip` — system clipboard integration on X11
   - `nodejs`, `npm` — Mason-installed LSPs (`bashls`, `pyright`, `ts_ls`)
4. Echo a one-line hint that `gopls` requires `go` on PATH; do not fail if absent.

### `.config/nvim/init.lua` (new)

Vendored copy of upstream [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) `init.lua` with three localized customizations.

**Customization 1 — LSP servers.** Inside the `servers = { ... }` table that kickstart already exposes for user editing, add entries for:

```lua
bashls = {},
pyright = {},
gopls = {},
ts_ls = {},
```

(Defaults are fine; the empty tables register them with Mason and `nvim-lspconfig`.)

**Customization 2 — Treesitter parsers.** Extend `ensure_installed` with `bash`, `python`, `go`, `typescript`, `tsx` (in addition to kickstart's defaults).

**Customization 3 — Formatters via conform.nvim.** Kickstart already wires `conform.nvim`; extend the `formatters_by_ft` table:

```lua
sh = { 'shfmt' },
python = { 'isort', 'black' },
go = { 'goimports', 'gofmt' },
typescript = { 'prettier' },
typescriptreact = { 'prettier' },
javascript = { 'prettier' },
```

**Header note.** Add a short comment block at the top of `init.lua` that:
- credits upstream kickstart.nvim with a link
- lists the three customization sites by line number / search anchor so future-the-user can find them quickly
- points at `:Tutor`, `:checkhealth`, and `:help` as learning entry points

### `scripts/test_programs.sh` (modify)

Add a `test_neovim_install` case following the existing pattern (PATH-prepended `$BIN_DIR` mocking, no network, no sudo).

Assertions:
- **Fresh run:** `add-apt-repository ppa:neovim-ppa/stable` is called; `apt-get install` is called with `neovim` and `nodejs` in its argument list.
- **Re-run:** When `nvim` is already on PATH (mocked), the script prints `Already installed: neovim` and does not invoke `add-apt-repository` or `apt-get`.

## Data flow / first-run UX

```
bash scripts/install.sh
  → stow .                                      # symlinks .config/nvim/init.lua → ~/.config/nvim/init.lua
  → scripts/programs/neovim.sh                  # apt-installs nvim + deps
  → (other programs continue)

nvim                                            # first launch
  → lazy.nvim bootstraps and installs plugins   # ~30s, blocks UI with progress
  → Mason kicks off LSP installs in background  # ~1min, async
  → editor is usable immediately, LSPs appear as they finish

:checkhealth                                    # one-shot verification
```

## Error handling

- `set -euo pipefail` in the install script: any apt failure aborts the script and the orchestrator records the failure in `.install_errors`.
- Idempotency guard prevents reinstall churn on re-runs of `install.sh`.
- `add-apt-repository` requires `software-properties-common`; the existing base-package step in `install.sh` already installs it. If a future change removes that, the neovim script will fail loudly — acceptable, since it's a real prerequisite.
- LSP install failures inside Mason are surfaced in nvim's `:Mason` UI; not the install script's concern.
- A missing `go` toolchain produces a Mason warning for `gopls` only; the rest of the editor is unaffected.

## Testing

### Automated

`scripts/test_programs.sh` adds the `test_neovim_install` case described above. Mocks `sudo`, `apt-get`, `add-apt-repository`, and `command` via `$BIN_DIR` PATH prepending — same technique used by the existing tpm/docker/terminator tests.

### Manual verification (post-install, on a real machine)

1. `bash scripts/programs/neovim.sh` — expect apt install output, no errors.
2. `bash scripts/programs/neovim.sh` — expect `Already installed: neovim`.
3. `nvim` — first launch shows lazy.nvim install progress; wait until it finishes and the dashboard appears.
4. `:checkhealth` — expect green for `lazy`, `mason`, `treesitter`, `telescope`. `gopls` may be yellow if Go is not installed (expected).
5. Open a `.sh`, `.py`, `.go`, and `.ts` file each and confirm:
   - Syntax highlighting (Treesitter)
   - LSP diagnostics appear after a moment (hover with `K`, go-to-def with `gd`)
   - `:Format` (or save, depending on conform config) runs the right formatter for each filetype
6. `:Telescope find_files` and `:Telescope live_grep` work — proves `fd` and `ripgrep` are wired up.

## Out of scope

- Custom keymaps beyond kickstart defaults — learn them first, customize when a real friction point appears.
- Custom colorscheme — kickstart ships `tokyonight`; change later.
- DAP (debugger) setup — add per-language when actually needed.
- Vim/Neovim coexistence concerns — the existing `.vimrc` in this repo is unchanged; `vim` and `nvim` remain independent.
- Migrating other dotfiles to depend on `nvim` (e.g., `EDITOR=nvim` in `.zshrc`) — separate, opinionated change; user can flip later.
