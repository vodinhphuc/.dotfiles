#!/bin/bash
set -euo pipefail

if command -v nvim &>/dev/null; then
    echo "Already installed: neovim"
    exit 0
fi

echo "Adding Neovim stable PPA..."
sudo add-apt-repository -y ppa:neovim-ppa/stable
sudo apt-get update

echo "Installing Neovim and dependencies..."
sudo apt-get install -y \
    neovim \
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
