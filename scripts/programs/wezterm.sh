#!/bin/bash
set -euo pipefail

# WezTerm -- GPU-accelerated terminal emulator, configured in Lua.
#
# Installed ALONGSIDE Terminator, not as a replacement: this script deliberately
# leaves update-alternatives and the GNOME default-terminal gsettings alone, so
# Ctrl+Alt+T keeps opening Terminator (see terminator.sh). Switch the default
# only after confirming Vietnamese input still works -- WezTerm speaks Wayland's
# zwp_text_input_v3 directly instead of going through GTK/VTE the way Terminator
# does, so ibus behaviour is not guaranteed to carry over.
#
# The config itself is a stowed dotfile (`.config/wezterm/wezterm.lua`); this
# script never writes it.

# The apt key and repo exist only to install the package, so they share its
# guard -- same shape as gh.sh. Steps that must survive on an already-provisioned
# machine (the wallpaper folder below) get their own guard instead.
if ! command -v wezterm &>/dev/null; then
    WEZTERM_KEYRING=/usr/share/keyrings/wezterm-fury.gpg
    echo "Adding WezTerm apt repo..."
    curl -fsSL https://apt.fury.io/wez/gpg.key |
        sudo gpg --batch --yes --dearmor -o "$WEZTERM_KEYRING"
    sudo chmod 644 "$WEZTERM_KEYRING"
    echo "deb [signed-by=$WEZTERM_KEYRING] https://apt.fury.io/wez/ * *" |
        sudo tee /etc/apt/sources.list.d/wezterm.list >/dev/null
    sudo apt-get update
    echo "Installing WezTerm..."
    sudo apt-get install -y wezterm
else
    echo "Already installed: wezterm"
fi

# Wallpapers the Lua config picks from at random. These ARE committed, so a
# `git pull` on another machine brings the backgrounds with it -- the whole point
# of keeping them in the dotfiles repo rather than in ~/Downloads. Guarded
# separately from the package so the folder is still created on a machine where
# WezTerm was installed before it existed.
WEZTERM_BG_DIR="${HOME}/.config/wezterm/bg"
if [ ! -d "$WEZTERM_BG_DIR" ]; then
    echo "Creating WezTerm background folder: $WEZTERM_BG_DIR"
    mkdir -p "$WEZTERM_BG_DIR"
else
    echo "Already installed: WezTerm background folder"
fi
