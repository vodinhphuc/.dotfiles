# Tmux User Guide

Reference for using `tmux` as configured by this dotfiles repo (`.tmux.conf`). The config is opinionated — most notably it changes the prefix from `Ctrl-b` to `Ctrl-Space` — so this guide takes precedence over generic tmux tutorials wherever they conflict.

---

## 1. What's installed

Tmux comes from `apt` (installed by `scripts/install.sh`'s base-package step). Plugins are managed by [TPM](https://github.com/tmux-plugins/tpm), bootstrapped by `scripts/programs/tpm.sh`, which auto-clones TPM and runs `install_plugins` on every install run.

Survival commands:
```bash
tmux                       # start a new unnamed session
tmux ls                    # list running sessions
tmux a                     # attach to the most recent
tmux a -t work             # attach by name
Ctrl-d                     # exit the current pane (closes it; if last, closes session)
```

To detach (keep session running, exit attach):
```
prefix d
```

`prefix` here means `Ctrl-Space` for you. See section 3.

---

## 2. Mental model

```
session
├── window 1
│   ├── pane (left)
│   └── pane (right)
├── window 2
│   └── pane
└── window 3
    ├── pane (top)
    └── pane (bottom)
```

- A **session** is a long-running process that survives terminal close. You attach to it; it keeps running when you detach.
- A **window** is like a browser tab inside the session.
- A **pane** is a split-view inside a window.

There are two interaction modes:

| Mode | How to enter | How to exit | What it does |
|---|---|---|---|
| Normal | (default after attach) | (already in it) | Type at your shell, run commands |
| Copy mode | `prefix [` | `q` or `Esc` | Scroll history, search, select-and-copy |

Most "tmux trickery" happens via the prefix in normal mode, or via vi-keys in copy mode.

---

## 3. Your prefix is `Ctrl-Space`, not `Ctrl-b`

Default tmux uses `Ctrl-b` as its prefix (everywhere on the internet). Your `.tmux.conf` rebinds:

```tmux
unbind C-b
set -g prefix C-Space
bind C-Space send-prefix
```

So **everywhere you read "prefix" in this guide** (or in any tmux blog post), press **`Ctrl-Space`**, not `Ctrl-b`.

If a nested process (e.g., a tmux session inside a tmux session, or a program that wants its own `Ctrl-Space`) needs to see `Ctrl-Space` as a key, press `prefix` then `Ctrl-Space` — that's what `bind C-Space send-prefix` is for: the second press passes through.

**Why change it?** `Ctrl-b` collides with readline's "move cursor back one char" — annoying if you ever attach without thinking. `Ctrl-Space` is unused by most shells.

---

## 4. Sessions

```bash
# from outside tmux
tmux new -s work                    # create session named "work"
tmux ls                             # list sessions
tmux a -t work                      # attach
tmux kill-session -t work           # kill from outside

# from inside tmux (prefix = Ctrl-Space)
prefix d                            # detach (session keeps running)
prefix s                            # list-and-jump session picker
prefix $                            # rename current session
prefix (   prefix )                 # cycle prev / next session
prefix L                            # toggle to last session
prefix : kill-session               # kill current (prefix : opens command line)
```

Practical pattern: one session per project.

```bash
cd ~/.dotfiles && tmux new -s dotfiles
cd ~/myproject && tmux new -s myproject
tmux ls
# 0: dotfiles ...
# 1: myproject ...
```

---

## 5. Windows

```
prefix c               create a new window (in current session)
prefix ,               rename current window
prefix &               kill current window (with confirm)
prefix 1..9            jump to window by index (your indices start at 1)
prefix n / prefix p    next / prev window
prefix l               toggle to last window
prefix f               find a window by content
prefix .               move current window to a different index
Alt-L / Alt-H          next / prev window — NO PREFIX (custom from your config)
```

Example: keep "editor", "shell", "logs" as windows 1/2/3 in the same session, jump between them with `Alt-L` / `Alt-H` without the prefix dance.

---

## 6. Panes

The interesting part. Your config customizes split keys to inherit the current pane's working directory, so a new split lands in the same `cwd`.

```
prefix v                split the current pane top/bottom (your custom; cwd inherited)
prefix h                split the current pane left/right (your custom; cwd inherited)
prefix x                kill current pane (with confirm)
prefix z                ZOOM toggle — current pane fills the window; press again to restore
prefix q                show pane numbers briefly; press a number to jump
prefix arrows           switch focus between panes
prefix Ctrl-arrows      resize the focused pane border by 1 cell
prefix Alt-arrows       resize by 5 cells
prefix !                "break" current pane out into its own window
prefix {  prefix }      swap current pane with the previous / next
prefix Space            cycle through layout presets (even-h, even-v, main-h, etc.)
prefix o                rotate panes (move focus to the next pane)
```

Default tmux uses `prefix %` for left/right and `prefix "` for top/bottom — those still work but are awkward. Your `prefix h` / `prefix v` are the ones to remember.

Note: `prefix v` makes a horizontal divider (one pane on top, one below — the `-v` flag means "vertical layout"). `prefix h` makes a vertical divider (left, right — the `-h` flag means "horizontal layout"). The letters refer to the divider orientation in your config.

---

## 7. Copy / paste

Your config sets vi-keys for copy mode and uses `tmux-yank` to sync to the system clipboard.

```
prefix [                enter copy mode
hjkl, w, b              move cursor (vi keys)
g  G                    top / bottom of buffer
/pattern Enter          search forward; n / N to repeat
v                       start a character selection (your keybind)
Ctrl-v                  toggle block selection (your keybind)
y                       copy selection AND exit copy mode (your keybind)
                        — also pushed to system clipboard via tmux-yank
q  Esc                  quit copy mode without copying

prefix ]                paste tmux's buffer in the current pane
                        — for system-clipboard paste in nvim/browser, use
                          your OS shortcut (Ctrl-Shift-V in most terminals)
```

Mouse drag (because `mouse on`) also enters copy mode and copies on release — convenient for one-off selections.

**System-clipboard sync needs `xclip` or `wl-clipboard`:**
- X11 (most Ubuntu desktops): `sudo apt install xclip`
- Wayland (newer GNOME): `sudo apt install wl-clipboard`

Check which you're on: `echo $XDG_SESSION_TYPE`.

If neither is installed, `y` still copies to tmux's internal buffer (so `prefix ]` works in tmux) — but `Ctrl-V` outside tmux won't see it.

---

## 8. Mouse

Your `.tmux.conf` enables mouse support:

```tmux
set -g mouse on
```

This enables:
- **Scroll wheel** → enters copy mode and scrolls history (`q` to leave)
- **Click on a pane** → focus it
- **Click on a window name** → switch to it
- **Drag a pane border** → resize the pane
- **Drag in a pane** → start a selection (releasing copies via tmux-yank)

To **bypass tmux entirely** (use the terminal's native mouse selection — useful when tmux's selection misbehaves), hold `Shift` while dragging.

---

## 9. Your plugins

Three plugins, all installed automatically by `scripts/programs/tpm.sh`:

### `catppuccin/tmux` — theme

A status-bar theme using the [catppuccin](https://github.com/catppuccin/catppuccin) palette. Your config picks the `mocha` flavor:

```tmux
set -g @plugin 'catppuccin/tmux'
set -g @catppuccin_flavour 'mocha'
```

To try a different flavor: change `mocha` to `latte` / `frappe` / `macchiato` and reload (`tmux source-file ~/.tmux.conf`). The plugin docs explain status-module customization (the commented `@catppuccin_status_modules_right` line in `.tmux.conf` is a starting point).

### `tmux-plugins/tmux-yank` — system-clipboard sync

What makes `y` in copy mode (and mouse-drag-release) actually push to your OS clipboard. No config needed. Requires `xclip` / `wl-clipboard` on the system as noted in section 7.

### `tmux-plugins/tmux-sensible` — sensible defaults

Tmux's defaults are old; `tmux-sensible` adjusts them:
- Faster `Esc` key recognition (no half-second delay — important for `nvim`)
- Bigger scrollback (50,000 lines)
- UTF-8 enabled
- `prefix R` — reload `.tmux.conf` (this is where your reload binding comes from; the message it prints is `sourced ~/.tmux.conf!`)
- A handful of vi-friendly tweaks for copy mode

### Adding a new plugin

1. Edit `.tmux.conf` and add `set -g @plugin 'owner/repo'` near the other plugin lines.
2. Either: from inside tmux, press `prefix I` (capital i) — TPM downloads and sources it. Or from the shell, run `bash scripts/programs/tpm.sh` — does the same idempotently.
3. The new plugin's docs will tell you what it adds (keybinds, options).

---

## 10. Customizations vs default tmux

Quick reference for the diff between this repo's tmux and stock:

| Setting | Default | This repo |
|---|---|---|
| Prefix | `Ctrl-b` | `Ctrl-Space` |
| Mouse | off | on |
| Window/pane indices | start at 0 | start at 1 |
| Renumber on close | off | on |
| Copy mode keys | emacs | vi |
| Split (horizontal divider) | `prefix "` | `prefix v`, inherits cwd |
| Split (vertical divider) | `prefix %` | `prefix h`, inherits cwd |
| Window nav | `prefix n` / `prefix p` only | also `Alt-L` / `Alt-H` (no prefix) |
| Color | 256 | true color (`-Tc`) |
| Copy `v` start-selection | not bound | bound |
| Copy `Ctrl-v` block toggle | not bound | bound |
| Copy `y` copy-and-cancel | `Enter` | `y` |

---

## 11. Common workflows

**"Run a long task and let it survive terminal close"**
```bash
tmux new -s build
make all
# detach with: prefix d
# reconnect later from any terminal:
tmux a -t build
```

**"Editor on the left, shell on the right"**
```bash
tmux new -s work
nvim .                         # open editor in pane 1
prefix h                       # split left/right
                               # focus jumps to the new pane (right)
                               # cwd inherited automatically
```

**"Session per project"**
```bash
cd ~/.dotfiles && tmux new -s dotfiles
# detach: prefix d
cd ~/myapp && tmux new -s myapp
tmux ls
# attach to whichever:
tmux a -t dotfiles
```

**"Reload `.tmux.conf` without restarting"**
- From inside tmux: `prefix R` (provided by `tmux-sensible`) — prints `sourced ~/.tmux.conf!`
- From outside: `tmux source-file ~/.tmux.conf`
- (No `prefix r` shortcut is bound by this repo specifically — `tmux-sensible`'s capital `R` is what you've got.)

**"Share a session between two terminals"**
```bash
# terminal A
tmux new -s pair
# terminal B
tmux a -t pair                 # both windows now show the same content;
                               # input from either reaches the same shell
```

**"Find an error in scrollback and copy the line"**
1. `prefix [` (enter copy mode)
2. `/error<Enter>` (search forward)
3. `n` to walk hits, `N` for backward
4. `V` for line-select (or `v` for char-select), then move cursor
5. `y` (copies + exits + lands in your system clipboard)
6. Paste into a browser / nvim / wherever with `Ctrl-Shift-V`

---

## 12. Troubleshooting

| Symptom | First thing to try |
|---|---|
| Colors look washed out / wrong | `echo $TERM` — should be `tmux-256color` or `screen-256color` inside tmux. If something else, kill all sessions and start fresh. Confirm `terminal-overrides ",xterm*:Tc"` is in `.tmux.conf`. |
| `prefix I` doesn't install plugins | Run `bash scripts/programs/tpm.sh`. If still nothing, `ls ~/.tmux/plugins/tpm/bin/install_plugins` — confirm TPM is actually cloned. |
| `y` copies in tmux but not into the OS clipboard | `command -v xclip wl-copy` — at least one must resolve. Install with `sudo apt install xclip` (X11) or `sudo apt install wl-clipboard` (Wayland). Check `echo $XDG_SESSION_TYPE` to know which. |
| Scroll behaves weirdly | You're in copy mode — press `q`. If you want native terminal scroll, hold `Shift` while scrolling. |
| Long delay after pressing `Esc` (especially in nvim) | `tmux-sensible` should fix it (`escape-time 0`). If not, confirm the plugin loaded with `prefix I` or `bash scripts/programs/tpm.sh`. |
| Pane keeps closing unexpectedly when running a script | The script ran `exit` or finished. Add `; bash` at the end to keep the shell alive after, or run the command in a wrapping shell. |
| Two-tmux nesting (e.g., SSH inside tmux) confuses the prefix | `prefix prefix` — the second `Ctrl-Space` passes through to the inner tmux thanks to `bind C-Space send-prefix`. |

---

## 13. Cheat sheet

Single table of every keybind covered above. **prefix** = `Ctrl-Space`.

### Sessions
| Keys | Action |
|---|---|
| `tmux new -s NAME` | create named session (from shell) |
| `tmux ls` | list sessions (from shell) |
| `tmux a -t NAME` | attach to session (from shell) |
| `prefix d` | detach |
| `prefix s` | session picker |
| `prefix $` | rename current session |
| `prefix (` / `prefix )` | prev / next session |
| `prefix L` | toggle to last session |

### Windows
| Keys | Action |
|---|---|
| `prefix c` | new window |
| `prefix ,` | rename window |
| `prefix &` | kill window |
| `prefix 1..9` | jump to window by index |
| `prefix n` / `prefix p` | next / prev window |
| `prefix l` | last window |
| `prefix f` | find by content |
| `Alt-L` / `Alt-H` | next / prev window (no prefix) |

### Panes
| Keys | Action |
|---|---|
| `prefix v` | split top/bottom (cwd inherited) |
| `prefix h` | split left/right (cwd inherited) |
| `prefix x` | kill pane |
| `prefix z` | zoom toggle |
| `prefix arrows` | move focus |
| `prefix Ctrl-arrows` | resize ±1 |
| `prefix Alt-arrows` | resize ±5 |
| `prefix q` | show pane numbers |
| `prefix !` | break pane to own window |
| `prefix {` / `prefix }` | swap with prev / next |
| `prefix Space` | cycle layouts |
| `prefix o` | rotate focus |

### Copy mode
| Keys | Action |
|---|---|
| `prefix [` | enter copy mode |
| `hjkl` `w` `b` `g` `G` | navigate (vi keys) |
| `/pattern <Enter>` | search forward; `n`/`N` repeat |
| `v` | start char selection |
| `Ctrl-v` | block-select toggle |
| `y` | copy + exit + sync to OS clipboard |
| `q` / `Esc` | quit copy mode |
| `prefix ]` | paste tmux buffer |

### Plugins / config
| Keys | Action |
|---|---|
| `prefix I` | TPM install missing plugins |
| `prefix R` | reload `.tmux.conf` (tmux-sensible) |
| `prefix :` | command-prompt (`source-file`, `kill-session`, etc.) |

---

End. Read `man tmux` if you want to go deeper.
