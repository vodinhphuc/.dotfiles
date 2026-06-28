#!/bin/bash
set -euo pipefail

# Visual Studio Code — installed from Microsoft's official apt repo (NOT snap).
# The snap is strictly confined and its launcher sanitizes the environment,
# dropping GTK_IM_MODULE/XMODIFIERS, so ibus input methods (e.g. ibus-unikey for
# Vietnamese) never reach the editor. The apt build runs unconfined and inherits
# the session env, so input methods work.
if ! command -v code &>/dev/null; then
    echo "Adding Microsoft VS Code apt repo..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
        sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/microsoft.gpg
    sudo chmod go+r /etc/apt/keyrings/microsoft.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
        sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
    sudo apt-get update
    echo "Installing Visual Studio Code..."
    sudo apt-get install -y code
else
    echo "Already installed: visual studio code"
fi
