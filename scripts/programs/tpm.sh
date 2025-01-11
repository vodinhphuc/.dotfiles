#!/bin/bash

echo "Installing Tmux plugins manager"

PLUGIN_DIR="~/.tmux/plugins"
TPM_DIR="~/.tmux/plugins/tpm"

if [ ! -d "$PLUGIN_DIR" ]; then
	echo "Create new folder for tmux plugins"
	mkdir -p ~/.tmux/plugins
	git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
elif [ ! -d "~/.tmux/plugins/tpm" ]; then
	echo "Cloning tmp to ~/.tmux/plugins"
	git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
else
  echo "Already installed: existed: ~/.tmux/plugins/tpm"
fi

