#!/bin/bash
set -euo pipefail

# WezTerm -- GPU-accelerated terminal emulator, configured in Lua.
#
# This is the default terminal (Ctrl+Alt+T) as of 2026-08-22. It was installed
# alongside Terminator first and only promoted after Vietnamese input was
# confirmed working in both the shell and nvim Normal mode -- WezTerm speaks
# Wayland's zwp_text_input_v3 directly instead of going through GTK/VTE the way
# Terminator does, so ibus behaviour did not carry over for free. Terminator is
# still installed and still registered as an alternative, just not the default.
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

# Default terminal, half one: the alternatives system. Priority 60 beats
# Terminator's 50. /usr/bin/wezterm is registered rather than the package's own
# /usr/bin/open-wezterm-here (priority 20) because the latter is
# `wezterm start --cwd "$PWD" -- "$@"`, which would hand a caller's `-e <cmd>`
# straight to exec as the program name; plain `wezterm -e <cmd>` is an alias for
# `wezterm start <cmd>` and honours the x-terminal-emulator convention.
# WEZTERM_ALT_LINK is a test hook: pointing it at a temp path keeps the suite
# deterministic instead of depending on what this machine's default happens to be.
WEZTERM_ALT_LINK="${WEZTERM_ALT_LINK:-/etc/alternatives/x-terminal-emulator}"
if [ "$(readlink -f "$WEZTERM_ALT_LINK" 2>/dev/null)" != "/usr/bin/wezterm" ]; then
    echo "Setting WezTerm as the default x-terminal-emulator..."
    sudo update-alternatives --install /usr/bin/x-terminal-emulator \
        x-terminal-emulator /usr/bin/wezterm 60
    sudo update-alternatives --set x-terminal-emulator /usr/bin/wezterm
else
    echo "Already installed: WezTerm as default x-terminal-emulator"
fi

# Default terminal, half two: GNOME's Ctrl+Alt+T reads these keys, not the
# alternatives system, so both have to be set. Skipped where gsettings is absent
# (a headless or non-GNOME box) rather than failing the whole script.
if command -v gsettings &>/dev/null; then
    if [ "$(gsettings get org.gnome.desktop.default-applications.terminal exec 2>/dev/null)" != "'/usr/bin/wezterm'" ]; then
        echo "Setting WezTerm as the GNOME default terminal..."
        gsettings set org.gnome.desktop.default-applications.terminal exec /usr/bin/wezterm
        gsettings set org.gnome.desktop.default-applications.terminal exec-arg "-e"
    else
        echo "Already installed: WezTerm as GNOME default terminal"
    fi
else
    echo "Skipping GNOME default terminal: gsettings not available"
fi
