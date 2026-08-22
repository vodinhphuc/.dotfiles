#!/bin/bash
set -euo pipefail

if ! command -v terminator &>/dev/null; then
    echo "Installing Terminator..."
    sudo apt-get install -y terminator
fi

# Seed a starter config ONLY when there isn't one.
#
# This used to be an unconditional `cat >`, described as "idempotent" -- it was
# not. Terminator's preferences GUI writes to this same file, so every
# install.sh run silently destroyed whatever had been set there (background
# image, font, profiles) and reset it to this bare template. Anything the user
# has customised now wins; delete the file to get the template back.
TERMINATOR_CONFIG="${HOME}/.config/terminator/config"
mkdir -p "$(dirname "$TERMINATOR_CONFIG")"
if [ -f "$TERMINATOR_CONFIG" ]; then
    echo "Already installed: Terminator config (leaving your settings alone)"
else
cat > "$TERMINATOR_CONFIG" << 'EOF'
[global_config]

[keybindings]
[profiles]
[[default]]
  audible_bell = True
  cursor_color = "#aaaaaa"
[layouts]
[[default]]
[[[window0]]]
  type = Window
  parent = ""
  size = 1920, 1080
  position = 100:100
[[[child1]]]
  type = Terminal
  parent = window0

[plugins]
EOF
echo "Terminator config written."
fi

# Register Terminator as an x-terminal-emulator option, but do NOT claim the
# default: wezterm.sh sets itself as the default (Ctrl+Alt+T) at priority 60,
# and if both scripts forced the setting the winner would come down to the order
# install.sh happens to run them in. Registering without --set keeps Terminator
# one `update-alternatives --config x-terminal-emulator` away.
sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/terminator 50
