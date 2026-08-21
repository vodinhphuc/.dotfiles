# Neovim Quick-Start Guide (with this dotfiles' kickstart.nvim setup)

This is your reference for using the Neovim configuration installed by `scripts/programs/neovim.sh` + the `init.lua` at `.config/nvim/init.lua`.

The setup is based on [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) with localized customizations for Bash, Python, Go, TypeScript, and Lua.

---

## 1. First launch

```bash
nvim                          # plain
nvim file.py                  # open a file
nvim .                        # opens netrw file explorer in cwd
```

**What happens the first time:**
1. `lazy.nvim` installs ~25 plugins (~30s, you see a UI). Don't interrupt.
2. Once you're at the dashboard, run `:Mason` — Mason will start installing your LSPs and formatters in the background. Wait until each shows ✓.
3. Run `:checkhealth` once. Anything red is broken; yellow is usually fine. `gopls` will be missing if you haven't installed Go yet.
4. Quit with `:qa` and relaunch — startup is now fast.

---

## 2. The mental model: modes

This is the one thing that confuses every beginner. Vim has modes — your keys do different things depending on which mode you're in.

| Mode | How to enter | Purpose |
|---|---|---|
| **Normal** | `Esc` (always) | Navigate, run commands, this is the "home" mode |
| **Insert** | `i` (insert), `a` (append), `o` (new line below), `O` (new line above) | Type text |
| **Visual** | `v` (char), `V` (line), `Ctrl-v` (block) | Select text |
| **Command** | `:` | Run `:Telescope`, `:w`, etc. |

**The rule:** when in doubt, press `Esc`. It always returns you to Normal. From Normal, you press `i` to type, `Esc` to navigate.

---

## 3. Survival keys (memorize these)

Normal mode:

```
h j k l         left, down, up, right (you can also use arrows)
w / b           next / prev word
0 / $           start / end of line
gg / G          top / bottom of file
{ }             jump paragraph up/down
Ctrl-d/u        half-page down/up
%               jump to matching bracket
/foo<Enter>     search forward; n / N to repeat
*               search the word under cursor
u               undo
Ctrl-r          redo
.               repeat last change (extremely powerful)

dd              delete line
yy              yank (copy) line
p / P           paste after / before cursor
x               delete char under cursor
r<char>         replace one char
ciw             change inner word (the killer combo)
diw             delete inner word
ci"             change inside quotes
da{             delete around braces (block + braces)

:w  :q  :wq  :q!     write / quit / write+quit / quit-discard
```

Once you have `i / Esc / hjkl / : / dd / yy / p / u / /` you can survive.

---

## 4. The leader key — how everything in kickstart is reached

Your **leader** is `<Space>`. Almost every kickstart feature is `<Space>` + something. After pressing `<Space>`, **`which-key` pops up a menu** showing what each next key does — so you don't have to memorize. Just press `<Space>` and read.

Top-level groups:

```
<Space>s...     SEARCH (Telescope)
<Space>r...     REFACTOR (rename, etc.)
<Space>c...     CODE actions
<Space>d...     DOCUMENT (symbols)
<Space>w...     WORKSPACE (symbols)
<Space>t...     TOGGLE (<Space>tw = line wrap)
<Space>m...     MARKDOWN (render / glow preview)
<Space>h...     git Hunks
<Space>q        quit / loclist
<Space>f        format buffer
```

The most-used ones day-to-day:

```
<Space><Space>  switch between open buffers
<Space>sf       find files in project (fuzzy)
<Space>sg       live grep across project (ripgrep)
<Space>s.       recent files
<Space>sw       search the word under cursor across the project
<Space>sh       search :help
<Space>sd       project diagnostics (errors/warnings)
<Space>sk       search keymaps (great for discovery)
<Space>sn       search inside your nvim config
<Space>/        fuzzy search in current buffer

<Space>f        format buffer (conform.nvim → stylua/black/prettier/…)
<Space>q        open diagnostics in location list
```

Inside any Telescope picker:
- `<C-n>` / `<C-p>` move
- `<Enter>` open
- `<C-x>` open in horizontal split, `<C-v>` vertical split, `<C-t>` new tab
- `<C-/>` shows help inside the picker

---

## 5. LSP (the IDE features) — only active when an LSP is attached

When you open a `.py`, `.go`, `.ts`, `.lua`, or `.sh` file, the matching LSP attaches automatically (after Mason finishes installing it). Then:

```
K               hover docs (press again to enter the popup)
gd              go to definition
gD              go to declaration
gr              find references (Telescope picker)
gI              go to implementation
<Space>D        go to type definition
<Space>ds       document symbols (this file)
<Space>ws       workspace symbols (the project)
<Space>rn       rename symbol (cross-file)
<Space>ca       code action menu (quick fixes, refactors)

[d  ]d          previous / next diagnostic
<C-]>           same as gd (vim classic)
<C-t>           jump back through location stack
<C-o> / <C-i>   jump back / forward in your jump history
```

After hitting `K` once, hit `K` again to enter the floating window so you can scroll inside it. Press `q` to close.

---

## 6. Format on save

`<Space>f` formats the current buffer using conform.nvim, which routes by filetype:

| filetype | formatter |
|---|---|
| `lua` | `stylua` |
| `sh` | `shfmt` |
| `python` | `isort` then `black` |
| `go` | `goimports` then `gofmt` |
| `typescript` / `typescriptreact` / `javascript` | `prettier` |

Kickstart also auto-formats on save by default. If a save feels slow, that's why.

To **temporarily disable** format-on-save for a buffer/session:
```
:let b:disable_autoformat = 1     " buffer
:let g:disable_autoformat = 1     " global
```

---

## 7. Git — gitsigns is wired

In any file under git:

```
]c  [c          next / prev hunk
<Space>hp       preview hunk
<Space>hr       reset hunk
<Space>hs       stage hunk
<Space>hb       blame line (full)
<Space>tb       toggle inline blame
<Space>tD       toggle deleted-line preview
```

For everything else, drop to a terminal: `:!git status`, or split a terminal `:terminal` (`Esc-Esc` to exit terminal-insert, then `:q`).

---

## 8. Multiple files / windows / tabs

```
:e path/to/file              open file
:vs / :sp                    vertical / horizontal split
:vs path/to/file             open in vertical split
Ctrl-w h/j/k/l               switch focus between splits
Ctrl-w =                     equalize split sizes
Ctrl-w c                     close current split
Ctrl-w o                     close all OTHER splits
Ctrl-w |  /  Ctrl-w _        max width / max height current split

:bn / :bp / :bd              next / prev / delete buffer
<Space><Space>               (kickstart) switch buffers via Telescope
<Space>e                     explorer (kickstart wires netrw or mini.files)
```

Don't go straight to tabs — most users use buffers + splits and rarely need tabs.

---

## 9. Per-language quick tips

### Python

- LSP: `pyright` (types, hover, goto, rename)
- Formatter chain: `isort` → `black`
- Try: open a `.py`, press `K` on a function call, then `gd`, then `gr` for references, then `<Space>rn` to rename a variable across files.

### Go

- LSP: `gopls` (only if you've installed Go via `apt install golang-go` or from go.dev — Mason will skip otherwise)
- Formatter chain: `goimports` → `gofmt` (auto-adds/removes imports on save)
- Bonus: `<Space>ca` after a Go syntax error often shows "Add import" and "Generate function" actions.

### TypeScript / JavaScript

- LSP: `ts_ls` (formerly `tsserver`)
- Formatter: `prettier`
- For React, you have `typescriptreact = { 'prettier' }`. JSX (`.jsx`) currently has no formatter — easy follow-up if you start writing `.jsx`.

### Bash

- LSP: `bashls` (catches uninitialized variables, syntax issues)
- Formatter: `shfmt`
- Tip: `:checkhealth` will warn if `shellcheck` isn't installed — it's optional but pairs well: `sudo apt install shellcheck`

### Lua (for editing your nvim config itself)

- LSP: `lua_ls` (knows the nvim API)
- Formatter: `stylua`
- Open `~/.config/nvim/init.lua` and you'll see hover docs for every `vim.*` call.

### Markdown (reading docs without leaving nvim)

Two complementary plugins, both lazy-loaded on `markdown` filetype:

```
<Space>mt       toggle in-buffer rendering (render-markdown.nvim)
<Space>mp       open the file in glow, in a floating window (glow.nvim)
:RenderMarkdown toggle | enable | disable
:Glow
```

- **`render-markdown.nvim` styles the buffer you're editing** — headings get
  backgrounds, `-` becomes `•`, `- [ ]` becomes `☐`, tables align, code blocks get
  a shaded background. It un-renders whichever line your cursor is on, so the raw
  markdown is always there when you need to type. This is on by default in any
  markdown file; `<Space>mt` turns it off if you want to see raw source.
- **`:Glow` / `<Space>mp` is the terminal `glow` you already use**, opened in a
  floating window over the buffer. Read-only pager — `q` closes it. Use this when
  you want the full paged, centered, glow-styled read rather than an edited buffer.

Both rely on the `markdown` and `markdown_inline` treesitter parsers (installed
automatically) and on a Nerd Font for the icons. `glow` itself comes from
`scripts/programs/glow.sh`. Verify with `:checkhealth render-markdown`.

**Three gotchas worth knowing up front:**

1. **`<Space>mt` is global and sticks for the session.** `:RenderMarkdown toggle`
   flips one flag for all buffers, not just the current one, and it stays flipped
   until you flip it back or restart nvim. So if a markdown file suddenly shows
   raw `#`, `**bold**` and `- [ ]` markup, you almost certainly brushed
   `<Space>mt` — `:RenderMarkdown enable` restores it.
2. **glow keeps the `##` on H2 and below.** Only H1 gets its `#` swallowed into a
   coloured block. That is glow's own dark theme, identical in your terminal — it
   is not a half-broken render.
3. **The float is coloured on purpose.** glow.nvim pipes glow's stdout instead of
   giving it a PTY, so glow decides it is "not a terminal" and drops every colour,
   leaving correct layout in flat grey. `init.lua` sets `CLICOLOR_FORCE=1` around
   the spawn (and only around the spawn — exporting it session-wide would force
   ANSI colour into ripgrep, git and the LSP servers, whose output nvim parses as
   plain text).

**Wide tables.** Several tables in this repo are 175-270 columns wide. With `wrap`
on, one row spills over three screen lines, and because render-markdown pads every
cell out to the widest column, the overflow is mostly blanks with the closing `|`
stranded on its own line. Two ways out:

```
<Space>tw       toggle 'wrap' -- off puts each row back on one line, scroll sideways
<Space>mp       read it in glow instead, which reflows cell contents to fit
```

`<Space>tw` is the better fix while editing (alignment is preserved); `:Glow` is
the better fix while reading, because render-markdown only pads and aligns -- it
never re-wraps text inside a cell, and has no `max_width` to cap a runaway table.

### Vietnamese input and Normal mode

Nothing to configure -- this happens automatically on a desktop session, and is
documented because the failure it prevents is baffling if you meet it cold.

**The problem.** With a Vietnamese IME active, ibus composes your keystrokes and
*commits* the result to the terminal, which forwards it as a **bracketed paste**.
Nvim inserts pasted text at the cursor in **any** mode. So with the IME on, every
Normal-mode key lands in the buffer instead of running a command: `<Space>sf`
types `sf` rather than opening Telescope. It looks exactly like being stuck in
Insert mode, and pressing `<Esc>` does not help, because you were never in Insert
mode to begin with.

It is not the keymap layer. `vim.paste({'sf'}, -1)` in Normal mode inserts `sf`
just the same.

**The fix.** `init.lua` switches the IME off on `InsertLeave` and restores it on
`InsertEnter`, so Normal mode always sees raw keys while Insert mode still gets
the real Unikey engine with its normal Telex behaviour. It also fires on
`VimEnter` (nvim starts in Normal mode) and restores on `VimLeavePre`, since
leaving the IME switched off would break typing everywhere else.

Guarded on `ibus` being present *and* a display being attached, so it does
nothing over SSH -- where the IME lives on the client -- or on WSL. Calls are
async: `ibus engine` takes 16-40ms here, enough to feel on every `<Esc>` if it
blocked.

**One consequence worth knowing:** if you switch input source with `Super+Space`
while in Normal mode, entering Insert restores whatever was active when you last
left Insert, overriding that choice. Switch while *in* Insert mode instead.

---

## 10. Common workflows (what you'll actually do)

**"Open a file in this project"**
1. `<Space>sf`, type a few letters of the filename, `<Enter>`.

**"Find every place this function is called"**
1. Cursor on the function name → `gr` → pick a result.

**"Rename this variable everywhere"**
1. Cursor on it → `<Space>rn` → type new name → `<Enter>`.

**"Why is this line red?"**
1. Cursor on it → `<Space>e` shows the error in a float (kickstart wires diagnostic-show on the leader). Or just `K`. Or `<Space>sd` to see all diagnostics.

**"Apply a quick-fix"**
1. Cursor on the squiggly line → `<Space>ca` → pick the action.

**"Search across the codebase for a string"**
1. `<Space>sg`, type query, press `<Enter>` on a result. Or `<Space>sw` to search for the word under your cursor.

**"Comment / uncomment a block"**
1. `gcc` toggles a single line. `gc` is an operator: `gcap` comments a paragraph, `gci{` comments inside braces. In visual mode: select with `V`, press `gc`.

---

## 11. Discovering more without leaving nvim

```
:Tutor              30-min interactive vim tutor (DO THIS once)
:VimBeGood          practice motions as a timed game (hjkl, dd/x, ci{, relative jumps)
:checkhealth        plugin / LSP / Mason status
:help <topic>       built-in docs (try :help vim-tutor or :help motion)
<Space>sh           Telescope through :help
<Space>sk           Telescope through every keymap that's set
:Lazy               plugin manager UI (:Lazy sync, :Lazy update, etc.)
:Mason              installer UI for LSPs/formatters (i to install, X to uninstall)
:LspInfo            which LSPs are running on this buffer
:ConformInfo        which formatter conform will use here
:messages           recent messages/errors that scrolled past
```

### Changing the colorscheme

The active theme is **catppuccin-mocha**, set in one place — the `catppuccin/nvim`
spec in `init.lua` (`flavour` + the `vim.cmd.colorscheme` call at the bottom of it).

```
:Telescope colorscheme enable_preview=true   preview every installed theme live (Esc cancels)
:colorscheme catppuccin-latte                the light flavour; also -frappe, -macchiato
:colorscheme tokyonight-night                the previous theme, kept installed for this
```

Those switches last until you restart. To make one permanent, edit the `colorscheme`
line in the spec. For a theme that isn't installed yet, add its plugin with
`priority = 1000` (so it loads before every other start plugin, otherwise the UI
flashes in default colours first) and run `:Lazy sync`.

---

## 12. Troubleshooting

| Symptom | First thing to try |
|---|---|
| LSP feels missing (no hover, no goto) | `:LspInfo` — is anything attached? `:Mason` — is it installed? |
| `<Space>f` does nothing on a file | `:ConformInfo` — does it know a formatter for this filetype? Is the formatter installed in `:Mason`? |
| `<Space>sf` says "ripgrep not found" or "fd not found" | `which rg fdfind` — should both resolve. If not, the `neovim.sh` install didn't run. |
| Plugins look broken after a manual `:Lazy update` | `:Lazy clean` then `:Lazy sync`. Worst case `rm -rf ~/.local/share/nvim ~/.local/state/nvim` and relaunch — your config (`init.lua`) is unaffected. |
| A markdown file shows raw `#` / `**bold**` / `- [ ]` instead of rendering | You hit `<Space>mt`. It toggles render-markdown **globally** for the rest of the session — `:RenderMarkdown enable` (or `<Space>mt` again) restores it. Restarting nvim also resets it. |
| Table rows sprawl over several lines with a stray `\|` alone on one | The table is wider than the window and `wrap` is on. `<Space>tw` turns wrap off (one row per line, scroll sideways); `<Space>mp` reads it in glow, which reflows cell contents. |
| `:Glow` opens but looks flat and grey | glow only colours output it thinks is a terminal. `init.lua` sets `CLICOLOR_FORCE=1` around the spawn — if you changed that spec, put it back. |
| You're trapped in some weird state | `Esc Esc Esc`, then `:q!` |
| Icons show as empty boxes (which-key, Telescope, statusline) | Font problem, not a config problem — see [`docs/troubleshooting/terminal-icons-tofu.md`](../troubleshooting/terminal-icons-tofu.md). Fonts are resolved by *your* terminal, so a remote client needs its own. |

---

## 13. Three habits to build early

1. **Stay in Normal mode by default.** Drop into Insert (`i`) only when you're typing actual text. The moment you stop typing — `Esc`. Most of your time should be spent navigating in Normal.

2. **Drill the motions deliberately.** `:VimBeGood` gives you timed exercises (`hjkl`, `dd`/`x`, `ci{`, relative-line jumps). Ten minutes of it beats an hour of guessing. `q` quits back to your buffer.

3. **When you find yourself reaching for the mouse or arrow keys, stop.** Look up the Normal-mode equivalent. The investment compounds. (The exception: scrolling docs / popups — mouse is fine, kickstart enables it.)

---

Run `:Tutor` once — it's 25 minutes and worth more than this whole guide.
