#!/bin/bash
set -euo pipefail

if command -v nvim &>/dev/null; then
    echo "Already installed: neovim"
    exit 0
fi

# Neovim itself comes from snap (classic confinement → full filesystem access).
# Earlier versions of this script used ppa:neovim-ppa/stable, but that PPA does
# not publish for non-LTS Ubuntu releases (e.g. 25.10 "questing"), causing
# `apt-get update` to 404. Snap maintains nvim across all Ubuntu versions.
echo "Installing Neovim via snap..."
sudo snap install nvim --classic

echo "Installing Neovim runtime dependencies via apt..."
sudo apt-get install -y \
    ripgrep \
    fd-find \
    git \
    build-essential \
    unzip \
    xclip \
    nodejs \
    npm

if ! command -v go &>/dev/null; then
    echo "Note: 'go' is not on PATH. Mason will skip gopls until Go is installed."
fi

echo "Neovim installation complete."
