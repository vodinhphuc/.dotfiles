#!/bin/bash

if [ ! -d ~/.tmux/plugins ]; then
    echo "Installing Tmux plugins manager"
	echo "Create new folder for tmux plugins"
	mkdir -p ~/.tmux/plugins
	git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

elif [ ! -d ~/.tmux/plugins/tpm ]; then
	echo "Cloning tpm to ~/.tmux/plugins"
	git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
else
  echo "Already installed: ~/.tmux/plugins/tpm"
fi

