#!/bin/bash
set -euo pipefail

# Nerd Font — a patched font supplying the Unicode Private Use Area glyphs that
# terminal UIs draw their icons from (which-key, telescope, lazy.nvim,
# powerlevel10k). Without one, those codepoints render as tofu boxes: pressing
# <Space> in Neovim showed U+F1050 as an empty square.
#
# Installed per-user into ~/.local/share/fonts rather than system-wide. No sudo
# is needed and fontconfig picks that directory up automatically.
#
# Guards are per-step, never a script-wide early exit — see the comment at the
# top of neovim.sh for why that pattern caused a real outage here.

FONT_NAME="${NERD_FONT_NAME:-JetBrainsMono}"
FONT_MATCH="${NERD_FONT_MATCH:-JetBrainsMono Nerd Font}"
FONT_DIR="$HOME/.local/share/fonts"

if fc-list 2>/dev/null | grep -qi "$FONT_MATCH"; then
    echo "Already installed: $FONT_MATCH"
else
    echo "Installing $FONT_NAME Nerd Font into $FONT_DIR..."
    mkdir -p "$FONT_DIR"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/extracted"

    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT_NAME}.zip" \
        -o "$tmp/font.zip"
    # Nerd Font archives ship docs alongside the faces; keep only the faces.
    unzip -q -o "$tmp/font.zip" -x 'README*' 'LICENSE*' -d "$tmp/extracted"
    find "$tmp/extracted" -type f \( -name '*.ttf' -o -name '*.otf' \) \
        -exec cp -f {} "$FONT_DIR/" \;

    echo "Refreshing font cache..."
    fc-cache -f "$FONT_DIR" >/dev/null

    echo "Installed: $FONT_MATCH"
fi

# Installing the font is only half of it. Neither step below can be automated
# safely: the terminal font lives in the emulator's own config (GUI or dconf),
# and flipping have_nerd_font while the terminal still uses an unpatched font
# would reintroduce exactly the tofu boxes this script exists to remove.
cat <<EOF

Two manual steps remain before icons appear:
  1. Point your terminal at the font.
     Terminator: Preferences > Profiles > General > Font -> "$FONT_MATCH Mono"
     Restart the terminal (and any tmux server: tmux kill-server).
  2. Set 'vim.g.have_nerd_font = true' in .config/nvim/init.lua
     Do this only after step 1 renders correctly.

Verify step 1 with:  echo -e "  "
(three distinct icons = working, boxes = font not applied yet)
EOF
