#!/bin/bash
set -euo pipefail

if ! command -v terminator &>/dev/null; then
    echo "Installing Terminator..."
    sudo apt-get install -y terminator
fi

# Always write/update config (idempotent)
mkdir -p "${HOME}/.config/terminator"
cat > "${HOME}/.config/terminator/config" << 'EOF'
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

# Set terminator as default terminal (Ctrl+Alt+T)
sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/terminator 50
sudo update-alternatives --set x-terminal-emulator /usr/bin/terminator
gsettings set org.gnome.desktop.default-applications.terminal exec /usr/bin/terminator
gsettings set org.gnome.desktop.default-applications.terminal exec-arg "-x"
