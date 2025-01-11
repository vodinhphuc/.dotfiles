#!/bin/bash
# Define the directory where tmux plugins will be stored
PLUGIN_DIR=~/.tmux/plugins
TPM_DIR=$PLUGIN_DIR/tpm

if [ ! -d "$TPM_DIR" ]; then
    echo "Installing Tmux plugins manager"
    echo "Creating folder for tmux plugins"
    mkdir -p "$PLUGIN_DIR"
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
    echo "Already installed: $TPM_DIR"
fi