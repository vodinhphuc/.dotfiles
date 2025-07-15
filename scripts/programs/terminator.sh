#!/bin/bash

which terminator &> /dev/null

if ! command -v terminator &> /dev/null; then
  echo "Installing Terminator..."
  sudo apt install -y terminator
  sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/terminator 50
else
  echo "Already installed: terminator"
fi
