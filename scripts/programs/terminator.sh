#!/bin/bash

which terminator &> /dev/null

if command -v terminator &> /dev/null; then
  #echo "Installing Terminator..."
  #sudo apt install -y terminator
  #sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/terminator 50
  # set terminator as default
  #gsettings set org.gnome.desktop.default-applications.terminal exec /usr/bin/terminator
  #gsettings set org.gnome.desktop.default-applications.terminal exec-arg "-x"
  #mkdir -p ~/.config/terminator
  #touch ~/.config/terminator/config
  cat > ~/.config/terminator/config << EOF
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
  size = 1920 , 1080
  position = 100:100
[[[child1]]]
  type = Terminal
  parent = window0


[plugins]
EOF
else
  echo "Already installed: terminator"
fi
