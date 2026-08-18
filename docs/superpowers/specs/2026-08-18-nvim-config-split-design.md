# Neovim config: split, quiet, and document

**Date:** 2026-08-18
**Status:** Approved, ready for planning
**Branch:** `feat/nvim-config-split`

## Problem

`.config/nvim/init.lua` is a vendored copy of [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) — 1027 lines in one file, 20 plugins, with local customizations layered in (bash/python/go/ts LSPs, formatters, stylua).

The 20 plugins are not bloat: subtract infrastructure (lazy.nvim, plenary, mason ×3, telescope extensions ×2) and ~10 user-facing features remain — LSP, completion, treesitter, fuzzy-find, git signs, formatting, which-key, colorscheme, mini.nvim, todo-comments. That is the minimal productive set.

> **Correction (2026-08-18).** An earlier revision of this spec claimed "the config is not broken," citing `nvim --headless "+qa"` exiting 0 with no errors. That measurement was real but the wrong test: the headless invocation exits before nvim-treesitter's asynchronous parser build runs, so it could not observe the failure. The config *was* broken — see [Resolved: missing tree-sitter CLI](#resolved-missing-tree-sitter-cli) below. Fixed separately; the split described here proceeds unchanged.

Four concrete pains, as stated by the user:

1. Doesn't know the keybindings.
2. Can't locate or safely edit things in the config.
3. Diagnostics are noisy while editing.
4. Too much on screen.

Pains 2–4 are addressable by structure and configuration. Pain 1 is a documentation gap.

Root causes:

- **1027 lines in one file.** The three customization anchors (LSP servers, treesitter parsers, formatters) are findable only via search comments at the top of the file.
- **`init.lua:197` sets `virtual_text = true`.** Every diagnostic renders as text at the end of its line, competing with code. This is the source of both pain 3 and pain 4.
- **No keybinding reference exists** in the repo.

## Resolved: missing tree-sitter CLI

Found and fixed while writing this spec. Separate from the split; recorded here because it falsified the "not broken" claim above.

**Symptom.** On every startup, nvim-treesitter re-downloaded all 15 configured parsers and failed to compile each one:

```
[nvim-treesitter/install/luadoc] error: Error during "tree-sitter build":
vim/_core/system:324: ENOENT: no such file or directory (cmd): 'tree-sitter'
```

**Root cause, two layers.**

1. The `tree-sitter` CLI was absent. nvim-treesitter's `main` branch builds parsers from source and requires it; apt does not ship it.
2. `scripts/programs/neovim.sh` opened with a script-wide guard — `command -v nvim && exit 0`. This machine installed nvim (v0.12.3) before commit `7bea06e` added the tree-sitter CLI step. Every subsequent run exited at that guard, so the new step was unreachable. `.install.log:2586` records `Already installed: neovim` with no tree-sitter line following it.

Layer 2 is the real defect: the guard made *any* dependency added after a machine's first provisioning permanently unreachable.

**Fix.** Replaced the script-wide guard with per-step guards — nvim binary, apt runtime deps (via `dpkg-query`), tree-sitter CLI — each printing `Already installed: <name>` when skipped, per the convention in `CLAUDE.md`. The CLI now installs unprivileged into `~/.npm-global` (already exported on PATH by `.zshrc:186`) instead of `sudo npm install -g`, which leaves root-owned files under `$HOME`.

**Regression test.** `scripts/test_programs.sh` gained a case asserting that with `nvim` present and `tree-sitter` absent, the script still installs the CLI, does not reinstall nvim, and does not use sudo. Verified failing against the old script before the fix. The prior "skip when already installed" case was also made hermetic — it previously ran with the real `$PATH` and would have invoked real `sudo`/`apt-get` once the early exit was removed.

**Verified.** 18 parsers compiled; `TSInstall` completes with zero errors; `neovim.sh` re-run is idempotent and needs no sudo.

## Non-goals

- Deleting plugins. Losing go-to-definition or fuzzy file search would make the user slower, not simpler.
- Rebuilding from zero on Neovim 0.12 native LSP. Considered and rejected: hand-installing `gopls`, `pyright`, and `shfmt` costs a week of lost productivity to re-reach today's baseline.
- Any change to `scripts/programs/neovim.sh`. It installs the binary and tree-sitter CLI; it does not touch config.
- Refactoring unrelated repo areas.

## Design

### 1. File layout

`~/.config/nvim` is a symlink to the whole `.dotfiles/.config/nvim` directory, so new subdirectories go live with no `stow` re-run.

| File | Approx. lines | Source range in current `init.lua` |
|---|---|---|
| `init.lua` | 40 | 1–109, 247–271, 1004–1027 (leader, bootstrap, lazy opts) |
| `lua/config/options.lua` | 70 | 110–180 |
| `lua/config/keymaps.lua` | 50 | 181–187, 204–234 |
| `lua/config/diagnostics.lua` | 25 | 188–202 |
| `lua/config/autocmds.lua` | 12 | 235–246 |
| `lua/plugins/lsp.lua` | 205 | 497–700 (mason, mason-lspconfig, mason-tool-installer, nvim-lspconfig, fidget) |
| `lua/plugins/telescope.lua` | 148 | 349–496 (telescope, fzf-native, ui-select, plenary, web-devicons) |
| `lua/plugins/completion.lua` | 97 | 753–849 (blink.cmp, LuaSnip) |
| `lua/plugins/format.lua` | 52 | 701–752 (conform.nvim) |
| `lua/plugins/treesitter.lua` | 68 | 922–989 |
| `lua/plugins/editor.lua` | 60 | 273, 290–320, 868–878, 879–921 (guess-indent, gitsigns, todo-comments, mini.nvim) |
| `lua/plugins/ui.lua` | 35 | 321–348, 850–867 (which-key, tokyonight) |

`init.lua` ends with `require('lazy').setup({ import = 'plugins' }, { ui = ... })`. lazy.nvim auto-loads every file under `lua/plugins/`; each returns a spec table. This is the structure used by [kickstart-modular.nvim](https://github.com/dam9000/kickstart-modular.nvim), so upstream kickstart documentation continues to apply.

The commented-out `kickstart.plugins.*` and `custom.plugins` import stubs at lines 990–1003 are dropped — `import = 'plugins'` supersedes them.

`lsp.lua` stays the largest at ~205 lines. Mason, lspconfig, and fidget are kept together as one concern rather than split across three files; the boundary is "everything about language servers."

**Effect on pain 2:** the three customization anchors become file locations rather than search strings.

- LSP servers → `lua/plugins/lsp.lua`
- Treesitter parsers → `lua/plugins/treesitter.lua`
- Formatters → `lua/plugins/format.lua`

### 2. Diagnostics

`lua/config/diagnostics.lua` changes one value from the current config:

```lua
vim.diagnostic.config {
  update_in_insert = false,
  severity_sort = true,
  underline = { severity = { min = vim.diagnostic.severity.WARN } },
  float = { border = 'rounded', source = 'if_many' },

  virtual_text = false,  -- was true
  virtual_lines = false,

  jump = { float = true },
}
```

Diagnostics remain visible as gutter signs and underlines. Full messages are read on demand:

- `]d` / `[d` — jump to next/previous diagnostic, message shown in a float (`jump = { float = true }`, unchanged).
- `<leader>e` — new keymap, `vim.diagnostic.open_float`, peek at the current line without moving the cursor.
- `<leader>q` — existing keymap, all diagnostics in the location list.

No diagnostic information is lost; only its unsolicited rendering is removed. This addresses pains 3 and 4.

### 3. Keybinding reference

`docs/guides/nvim.md`, following the structure of the existing `docs/guides/rgb.md`:

- A "start here" table of ~10 keys covering the daily loop: find file, grep, save, go-to-definition, rename, format, diagnostics.
- Remaining keymaps grouped by task (search, LSP, git, windows, diagnostics), each with its source file so the doc points back at editable config.
- A short note on discovery: `which-key` (press `<space>` and pause), `:Tutor`, `:checkhealth`.

Linked from the `README.md` guides table and referenced in the `CLAUDE.md` Neovim section. This addresses pain 1.

## Verification

The split is pure code movement and must be provably behavior-neutral.

Captured before and diffed after:

1. `nvim --headless "+qa"` — exit 0, no stderr output. **Not sufficient on its own:** this exits before asynchronous work (parser builds, LSP attach) runs, which is exactly how the tree-sitter failure above went unnoticed. Pair it with a run that holds the editor open long enough for async work to report — `nvim --headless "+sleep 20" "+qa"` on a real source file — and grep the output for `error`.
2. `nvim --headless "+Lazy! sync" "+qa"` then the sorted plugin-name list from `lazy-lock.json` — identical set of 20 plugins.
3. `nvim --headless --startuptime` — same order of magnitude (~30ms); a large regression means something is loading eagerly that previously did not.
4. `vim.diagnostic.config()` dump — differs in exactly one key, `virtual_text`.

Manual check on a real file: open a Go or Python source file with a deliberate error, confirm the gutter sign appears, no end-of-line text appears, and `]d` shows the message in a float.

Rollback: the entire change lives on `feat/nvim-config-split`. `git revert` restores today's config exactly, since the current `init.lua` remains in history at `dd431b8`.

## Out of scope for this spec

Trimming the plugin set. Once the config is split and the user has lived with the cheatsheet, individual plugins become easy to evaluate and remove one file at a time. That is a separate decision made with usage evidence, not upfront.
