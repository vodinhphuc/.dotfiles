# CLI Readers — `glow` + `bat`

Reference for reading rendered markdown and syntax-highlighted source in the terminal. Both tools are installed by `scripts/programs/glow.sh`.

---

## What's installed

- **`glow`** (apt, from Charm's repo) — terminal markdown renderer. Beautiful headings/lists/tables/code-blocks, built-in pager, multiple themes. Best fit for prose, READMEs, and `.md` docs. (Earlier this was a snap install; the snap's strict confinement blocked reads from `~/.dotfiles/`. The apt build runs unconfined.)
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
| `glow: command not found` after install | `hash -r` to refresh the shell's command cache, or open a new terminal. |
| Glow renders blank / wrong colors under tmux | Confirm `echo $TERM` is `screen-256color` inside tmux and `xterm-256color` outside. Confirm `.tmux.conf` has the `Tc` override. |
| `bat` paging is annoying for piping | Use `bat -p` (plain) or `bat --paging=never`. |
| Wrong theme | `bat --list-themes` then `export BAT_THEME="..."` in `.zshrc`. |
| `glow: permission denied` reading a file under `~/.dotfiles/` | You still have the old snap-installed glow on PATH. Run `sudo snap remove glow` then `bash scripts/programs/glow.sh && hash -r`. |

---

## Why these two

- **`glow` over `mdcat`** — mdcat tries to inline images via Kitty/iTerm graphics protocols, which break inside tmux. Glow doesn't render images, only text — safer in tmux.
- **`glow` over `frogmouth`** — Frogmouth is a TUI browser. Heavier startup, more for "read and navigate" sessions. Glow is faster for "open and read".
- **`bat` over `cat`** — `cat` has zero awareness of file structure. `bat` shows line numbers, syntax-highlights ~150 languages, and reuses `less` for paging. The plain mode (`bat -p`) is a drop-in replacement for `cat | less`.
