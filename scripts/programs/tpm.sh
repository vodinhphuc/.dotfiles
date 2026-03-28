#!/bin/bash
set -euo pipefail

TPM_DIR="${HOME}/.tmux/plugins/tpm"

if [ ! -d "$TPM_DIR" ]; then
    echo "Installing Tmux Plugin Manager..."
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
    echo "Already installed: $TPM_DIR"
fi