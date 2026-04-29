#!/bin/bash
set -euo pipefail

# glow — terminal markdown renderer (snap, classic confinement)
if ! command -v glow &>/dev/null; then
    echo "Installing glow..."
    sudo snap install glow
else
    echo "Already installed: glow"
fi

# bat — syntax-highlighted cat (Ubuntu ships the binary as `batcat` due to a
# name conflict with bacula-console-qt; the `bat` alias is wired in .zshrc)
if ! command -v batcat &>/dev/null; then
    echo "Installing bat..."
    sudo apt-get install -y bat
else
    echo "Already installed: bat"
fi
