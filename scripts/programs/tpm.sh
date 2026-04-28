#!/bin/bash
set -euo pipefail

TPM_DIR="${HOME}/.tmux/plugins/tpm"

if [ ! -d "$TPM_DIR" ]; then
    echo "Installing Tmux Plugin Manager..."
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
    echo "Already installed: $TPM_DIR"
fi

# Install/update plugins listed in ~/.tmux.conf (idempotent).
# install_plugins is provided by TPM and is a no-op for already-installed plugins.
if [ -x "$TPM_DIR/bin/install_plugins" ]; then
    echo "Installing tmux plugins from .tmux.conf..."
    "$TPM_DIR/bin/install_plugins"
fi
