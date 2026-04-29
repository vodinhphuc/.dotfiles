# Tmux User Guide — Design

**Date:** 2026-04-29
**Scope:** Add a comprehensive user guide for the tmux setup defined in this dotfiles repo (`.tmux.conf`). Single file, no code changes.

## Goal

A grep-friendly, learn-friendly reference at `docs/guides/tmux.md` that explains how to use tmux as configured by this repo — covering the mental model, every keybind from `.tmux.conf`, plugin behavior, common workflows, and troubleshooting. Modeled on `docs/guides/nvim.md` in tone and depth (~300 lines).

The guide must reflect THIS repo's config, not stock tmux. Notably:

- Prefix is `Ctrl-Space` (not the default `Ctrl-b`)
- Mouse is on; copy-mode is vi-keys
- Custom split bindings: `prefix+v` (top/bottom), `prefix+h` (left/right), both inherit current pane path
- Window navigation: `Alt+H` / `Alt+L` (no prefix needed)
- Indices start at 1 (windows and panes); auto-renumber on close
- Plugins: `catppuccin/tmux` (mocha theme), `tmux-plugins/tmux-yank` (system clipboard), `tmux-plugins/tmux-sensible` (sensible defaults)

## Decisions

1. **Single doc, no decomposition.** A multi-file guide (e.g., `tmux/sessions.md`, `tmux/panes.md`) would scatter the reference. One file is searchable and matches the precedent set by `docs/guides/nvim.md` (~300 lines) and `docs/guides/cli-readers.md` (~150 lines).
2. **Comprehensive over reference.** User explicitly chose "comprehensive" over "reference-only" — they want a learning resource as well as a quick-grep cheatsheet, including the mental model section.
3. **Lead with the prefix change.** The prefix being `Ctrl-Space` (not `Ctrl-b`) is the single biggest divergence from any third-party tmux tutorial. Surface it early, before any keybind tables, to prevent the reader from copy-pasting `Ctrl-b ...` from the internet and getting confused.
4. **Cheat sheet at the bottom.** A single-table summary of every keybind — for fast lookup once the reader knows the basics. Avoids forcing them to scan the full guide each time.
5. **Document the plugin-add workflow.** Include short instructions for adding a new plugin (edit `.tmux.conf`, run `prefix+I` OR `bash scripts/programs/tpm.sh`) so the user can grow the setup later without re-asking.
6. **Out of scope: adding new plugins or themes.** This is a docs-only PR. Anything that would change behavior (new plugin, different theme, new keybind) is a separate feature task.

## Components

### `docs/guides/tmux.md` (new, ~300 lines)

Section outline (in order):

1. **What's installed (and how to use it right now)** — `tmux` / `tmux ls` / `tmux a` / `Ctrl-d` survival commands. Two-paragraph intro.
2. **Mental model** — sessions → windows → panes hierarchy diagram in ASCII; the prefix; normal vs copy mode.
3. **Your prefix is `Ctrl-Space`, not `Ctrl-b`** — early callout. Why we changed it (Ctrl-b conflicts with readline). How to "send the prefix through" if a nested process needs it (`prefix+prefix`).
4. **Sessions** — `tmux new -s <name>`, `tmux ls`, `tmux a -t <name>`, `tmux kill-session -t <name>`, `prefix+s` (Telescope-like picker), `prefix+$` (rename), `prefix+d` (detach).
5. **Windows** — `prefix+c` create, `prefix+,` rename, `prefix+&` close, `prefix+0..9` jump by index, `prefix+n` / `prefix+p` next/prev, `Alt+L` / `Alt+H` (custom — no prefix), `prefix+f` find.
6. **Panes** — `prefix+v` split top/bottom (your custom; inherits cwd), `prefix+h` split left/right (your custom; inherits cwd), `prefix+arrows` navigate, `prefix+Ctrl-arrows` resize, `prefix+z` zoom, `prefix+x` close, `prefix+!` break-pane-to-window, `prefix+{` / `prefix+}` swap, `prefix+Space` toggle layouts.
7. **Copy / paste (vi-mode + tmux-yank)** — the same flow we walked through in conversation: `prefix+[` enter copy mode, `v` start selection, `Ctrl-v` block-toggle, `y` copy-and-cancel (synced to system clipboard via tmux-yank). Mouse drag also copies. `prefix+]` paste tmux's buffer; OS-paste (`Ctrl-Shift-V`) for system clipboard. Note about `xclip` / `wl-copy` deps for tmux-yank.
8. **Mouse** — `set -g mouse on` enables: scroll-into-history, click-to-focus pane, drag-to-resize pane border, drag-to-select-and-copy. To bypass tmux entirely (rare), hold `Shift` while dragging.
9. **Your plugins** — three plugins, each with one paragraph + how to verify it's loaded:
   - `catppuccin/tmux` — mocha theme; status-bar styling.
   - `tmux-plugins/tmux-yank` — system-clipboard sync on `y` and on mouse-drag-release.
   - `tmux-plugins/tmux-sensible` — faster `Esc` register, longer scrollback, UTF-8, vi mode polish, etc.
   Plus: how to add a new plugin (edit `.tmux.conf`, then `prefix+I` or re-run `bash scripts/programs/tpm.sh`).
10. **Customizations vs default tmux** — small reference table:
    | Setting | Default | This repo |
    |---|---|---|
    | Prefix | `Ctrl-b` | `Ctrl-Space` |
    | Mouse | off | on |
    | Window/pane indices | start at 0 | start at 1 |
    | Renumber on close | off | on |
    | Copy mode keys | emacs | vi |
    | Splits | `prefix+%`, `prefix+"` | `prefix+h`, `prefix+v` (both inherit cwd) |
    | Window nav | `prefix+n`, `prefix+p` | also `Alt+L`, `Alt+H` (no prefix) |
    | Color | 256 | true color (`-Tc`) |
11. **Common workflows** — six concrete recipes:
    - Detach a long-running task (`tmux new -s build && long-cmd && exit`)
    - Two-pane side-by-side layout for editor + terminal
    - Session per project (`tmux new -s ~/.dotfiles`, `tmux a -t ~/.dotfiles`)
    - Reload config without restart (`tmux source-file ~/.tmux.conf` from outside, or `prefix+:` then `source-file ~/.tmux.conf` from inside; note the current config does not bind a `prefix+r` shortcut)
    - Share a session between two terminal windows
    - Search scrollback for an error then copy a line
12. **Troubleshooting** — table of symptom → first-thing-to-try:
    - Colors look washed out → check `$TERM` inside vs outside tmux
    - `prefix+I` doesn't install plugins → run `bash scripts/programs/tpm.sh`
    - `y` copies in tmux but not into the OS clipboard → `apt install xclip` or `wl-clipboard`
    - Scrolling jumps weirdly → mouse mode is on; press `q` if you're in copy mode
    - Long delay after `Esc` → tmux-sensible should fix it; if not, double-check the plugin loaded
13. **Cheat sheet** — single table of every keybind covered above, for fast grep.

## Data flow / first-read UX

```
nvim ~/docs/guides/tmux.md         # via the existing stow symlink
# OR
glow ~/.dotfiles/docs/guides/tmux.md
```

The user is expected to read top-down once, then grep into the cheat sheet for daily reference.

## Out of scope

- Adding any new plugin (resurrect, fzf, fingers, etc.) — separate feature.
- Switching themes from catppuccin or modifying its variant — separate change.
- Adding new keybinds (e.g., `prefix+r` to reload — not yet bound, only mentioned conditionally in the workflow section).
- General tmux upstream documentation — link to `man tmux` and `:help` for things outside this repo's config.

## Testing

No automated testing (docs only). Manual verification:

1. `markdownlint docs/guides/tmux.md` if installed (optional).
2. Visual render in `glow docs/guides/tmux.md` — no broken tables, headers in the expected hierarchy.
3. Spot-check 5 random keybinds in the cheat sheet against the live `.tmux.conf` to confirm correctness.
4. Confirm every claim about plugin behavior matches the actual installed plugin (e.g., catppuccin's status bar, tmux-yank's mouse-release copy).
