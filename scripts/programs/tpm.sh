#!/bin/bash

echo "Installing Tmux plugins manager"

if [ ! -d "~/.tmux/plugins/tpm" ]; then
  mkdir -p ~/.tmux/plugins
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
else
  echo "Already installed: existed: ~/.tmux/plugins/tpm"
fi

