#!/bin/bash

which terminator &> /dev/null

if ! command -v terminator &> /dev/null; then
  echo "Installing Terminator..."
  sudo apt install -y terminator
  sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/terminator 50
  # set terminator as default
  gsettings set org.gnome.desktop.default-applications.terminal exec /usr/bin/terminator
  gsettings set org.gnome.desktop.default-applications.terminal exec-arg "-x"

else
  echo "Already installed: terminator"
fi
