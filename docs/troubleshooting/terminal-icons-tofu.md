# Icons render as tofu boxes (Nerd Font glyphs missing)

Symptom: instead of icons you get empty rectangles — in Neovim's which-key popup
when you press `<Space>`, in Telescope, in the statusline, in `:Lazy`, or in the
powerlevel10k prompt. Sometimes on the desktop, sometimes only when connected
from a phone/tablet.

The glyphs live in the Unicode **Private Use Area** (U+E000–U+F8FF and
U+F0000–U+FFFFD). Only *patched* fonts — Nerd Fonts — carry them. Everything
else draws a box.

The single most important fact: **fonts are resolved by the terminal in front of
you, never by the machine you are connected to.** SSH transmits bytes. Installing
a font on the server does nothing for a remote client.

---

## Triage

Run these on the machine whose screen you are looking at.

```bash
# 1. Does a Nerd Font exist on THIS device?
fc-list 2>/dev/null | grep -ic nerd

# 2. Do raw glyphs render, outside any program?
echo -e "   "     # folder, code, arrow, house

# 3. Is Neovim even asked to emit icons?
nvim --headless '+lua print(vim.g.have_nerd_font)' +qa
```

| Observation | Cause |
|---|---|
| (1) is `0` on a local desktop | [No font installed](#1-no-nerd-font-installed) |
| (1) is non-zero but (2) shows boxes | [Terminal not pointed at the font](#2-terminal-not-using-the-font) |
| (2) renders, but nvim shows boxes on `<Space>` | [which-key emits PUA glyphs regardless of the flag](#4-which-key-ignores-have_nerd_font-for-key-labels) |
| (2) renders, nvim shows no icons at all | (3) prints `false` → [flag off](#3-have_nerd_font-is-false) |
| Fine locally, boxes over SSH | [Remote client has no font](#5-remote-client-termux-ssh-app-web-terminal) |
| Was fine, broke right after a font change | [tmux cached the old metrics](#6-tmux-holding-stale-cell-metrics) |

`fc-list` is unavailable on Android/Termux — for that client skip to cause 5.

---

## 1. No Nerd Font installed

**Confirm**

```console
$ fc-list | grep -ic nerd
0
```

**Fix** — `scripts/programs/nerd_font.sh` installs JetBrainsMono per-user into
`~/.local/share/fonts` (no sudo, fontconfig picks it up automatically):

```bash
bash scripts/programs/nerd_font.sh
```

Override the font with `NERD_FONT_NAME` / `NERD_FONT_MATCH`:

```bash
NERD_FONT_NAME=FiraCode NERD_FONT_MATCH="FiraCode Nerd Font" \
  bash scripts/programs/nerd_font.sh
```

**Verify**

```console
$ fc-list | grep -ic "JetBrainsMono Nerd Font"
48
$ fc-list : family | tr ',' '\n' | grep -i "jetbrainsmono nerd" | sort -u
JetBrainsMono Nerd Font
JetBrainsMono Nerd Font Mono
JetBrainsMono Nerd Font Propo
```

Installing the font is only half the job — continue to cause 2.

---

## 2. Terminal not using the font

Fontconfig knowing about a font does not make your terminal draw with it.

**Fix (Terminator)** — Preferences → Profiles → General:

1. Untick **Use the system fixed width font**
2. Set the font to **`JetBrainsMono Nerd Font Mono`**

Pick the **Mono** variant. `Nerd Font` and `Nerd Font Propo` use wider icon
glyphs that break column alignment in Neovim and tmux; `Nerd Font Mono` forces
every icon into one cell.

Match the size your system font used, so nothing else shifts:

```bash
gsettings get org.gnome.desktop.interface monospace-font-name   # e.g. 'Ubuntu Sans Mono 11'
```

**Verify** with the triage command 2. Four distinct icons = working.

---

## 3. `have_nerd_font` is false

`.config/nvim/init.lua` gates every icon in the config on one flag:

```lua
vim.g.have_nerd_font = true
```

It controls which-key's mapping icons, `mini.statusline`'s `use_icons`,
lazy.nvim's UI icons, and whether `nvim-web-devicons` is installed **at all** —
it is declared `enabled = vim.g.have_nerd_font`, so while the flag is false
lazy.nvim never downloads it.

**Set it only after causes 1 and 2 are confirmed fixed.** Flipping it while the
terminal still uses an unpatched font reintroduces boxes everywhere.

After flipping, install the newly-enabled plugin:

```bash
nvim --headless "+Lazy! sync" +qa
```

**Verify** — the plugin count should grow by one (20 → 21 here):

```bash
python3 -c "import json;d=json.load(open('.config/nvim/lazy-lock.json'));print(len(d), 'nvim-web-devicons' in d)"
```

---

## 4. which-key ignores `have_nerd_font` for key labels

The one that is genuinely not your fault. Upstream kickstart wires the flag to
which-key like this:

```lua
icons = { mappings = vim.g.have_nerd_font },
```

That correctly suppresses the icon beside each *description*. But which-key's
`icons.keys` table — the labels for `<Space>`, `<Esc>`, `<CR>`, `<BS>` — is
**independent of that option** and defaults to Nerd Font glyphs regardless:

```console
$ nvim --headless '+lua print(vim.inspect(require("which-key.config").options.icons))' +qa
{
  keys = {
    BS = "󰁮",        -- U+F006E
    CR = "󰌑 ",       -- U+F0311
    Esc = "󱊷 ",      -- U+F12B7
    Space = "󱁐 ",    -- U+F1050   <- the box you see on <Space>
    ...
  },
  mappings = false,          -- the flag DID take effect, just not here
  separator = "➜"            -- U+279C, a dingbat many monospace fonts lack
}
```

**Fix** — override `icons.keys` with plain text on the no-font branch. Already
applied in `.config/nvim/init.lua` (commit `86ddc77`):

```lua
icons = {
  mappings = vim.g.have_nerd_font,
  keys = vim.g.have_nerd_font and {} or {
    Space = 'Space ', Esc = 'Esc ', BS = 'BS ', CR = 'CR ',
    -- ...one entry per special key...
  },
  separator = vim.g.have_nerd_font and '➜' or '->',
},
```

`{}` on the true branch means "keep which-key's defaults", so the icons come
back automatically once a font is present.

**Verify** — dump the resolved config and assert no Private Use Area codepoints
survive when the flag is false:

```bash
nvim --headless '+lua local i=require("which-key.config").options.icons
  local f=io.open("/tmp/wk.txt","w") f:write(vim.inspect(i)) f:close()' +qa
python3 -c "
t=open('/tmp/wk.txt',encoding='utf-8').read()
print(sum(1 for c in t if 0xE000<=ord(c)<=0xF8FF or 0xF0000<=ord(c)<=0xFFFFD))"
```

---

## 5. Remote client (Termux, SSH app, web terminal)

Everything above fixes the **desktop**. A tablet or phone connecting over
SSH/Tailscale renders with its own font and is completely unaffected.

**Confirm the server is innocent** — the bytes on the wire are correct:

```console
$ printf '   \n' | hexdump -C
00000000  ef 81 bb 20 ef 84 a1 20  ee 82 b0 20 ef 80 95 0a
$ locale | grep LANG
LANG=en_US.UTF-8
```

`ef81bb` is UTF-8 for U+F07B. The server is emitting exactly the right thing;
the client simply cannot draw it.

**Fix (Termux on Android)** — run this **in Termux itself**, not inside the SSH
session. Termux reads exactly one font, from exactly one path, and has no font
picker:

```bash
pkg install -y curl unzip
mkdir -p ~/.termux
curl -fL -o "$TMPDIR/jbm.zip" \
  https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
unzip -o "$TMPDIR/jbm.zip" -d "$TMPDIR/jbm"
cp "$TMPDIR/jbm/JetBrainsMonoNerdFontMono-Regular.ttf" ~/.termux/font.ttf
termux-reload-settings
```

For other clients the same rule applies — install a Nerd Font on the *device*,
then select it in that client's own settings.

No server-side change is needed. `have_nerd_font = true` stays correct for every
client, because it only decides which bytes Neovim emits.

---

## 6. tmux holding stale cell metrics

After any font change, an already-running tmux server keeps the old cell
dimensions. Icons then look half-broken — clipped, overlapping, or misaligned —
even though the font is correct.

```bash
tmux kill-server     # then reconnect
```

Do this on the machine running the tmux **server** (the SSH target), not the
client.

---

## Lessons learned

- **Ask "which device draws this?" before anything else.** Font problems are
  client-side, always. Ten minutes went into the tablet before it clicked that
  the desktop's font was irrelevant to it.
- **A flag named `have_nerd_font` does not necessarily reach every icon.** Cause
  4 looked like the flag was broken; the flag worked perfectly and simply had no
  wiring to `icons.keys`. Dump a plugin's *resolved* config instead of trusting
  what the option name implies.
- **Codepoint ranges beat guessing.** Classifying a glyph as PUA
  (U+E000–U+F8FF, U+F0000–U+FFFFD) says immediately whether *any* normal font
  could have rendered it. `»` and `…` are safe everywhere; `➜` is a dingbat that
  some monospace fonts lack; anything in PUA needs a patched font, full stop.
- **`nvim --headless "+qa"` is a weak health check.** It exits before
  asynchronous work runs. Hold the editor open (`+sleep 15`) on a real file
  before concluding a config is clean.

---

## Related

- `scripts/programs/nerd_font.sh` — the installer (native-only; on WSL the
  Windows terminal supplies the font)
- [`docs/guides/nvim.md`](../guides/nvim.md) — the Neovim config these icons appear in
- [`docs/guides/tmux.md`](../guides/tmux.md) — tmux basics, if cause 6 is new to you
