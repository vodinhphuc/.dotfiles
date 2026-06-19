#!/bin/bash
set -euo pipefail

if command -v nvim &>/dev/null; then
    echo "Already installed: neovim"
    exit 0
fi

# Resolve the install target: honor ENVIRONMENT exported by install.sh, else
# detect WSL ourselves so the script still works when run standalone.
if [ -z "${ENVIRONMENT:-}" ]; then
    if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        ENVIRONMENT="wsl"
    else
        ENVIRONMENT="native"
    fi
fi

# Neovim install source depends on the target:
# - native: snap (classic confinement → full filesystem access). The neovim PPA
#   does not publish for non-LTS releases (e.g. 25.10 "questing"), so snap is the
#   reliable cross-version source on a desktop.
# - WSL: snap needs systemd, which is off by default, so snap installs fail.
#   Use the official static release tarball under /opt + a symlink on PATH.
if [ "$ENVIRONMENT" = "wsl" ]; then
    echo "Installing Neovim from official release tarball (WSL)..."
    case "$(uname -m)" in
        x86_64)        asset="nvim-linux-x86_64" ;;
        aarch64|arm64) asset="nvim-linux-arm64" ;;
        *) echo "Unsupported architecture for tarball install: $(uname -m)" >&2; exit 1 ;;
    esac
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/${asset}.tar.gz" \
        -o "$tmp/nvim.tar.gz"
    sudo rm -rf /opt/nvim
    sudo mkdir -p /opt/nvim
    sudo tar -xzf "$tmp/nvim.tar.gz" -C /opt/nvim --strip-components=1
    sudo ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
else
    echo "Installing Neovim via snap..."
    sudo snap install nvim --classic
fi

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

# nvim-treesitter (main branch, vendored in init.lua) builds parsers from source
# via the tree-sitter CLI. apt does not ship it; install via npm (just installed
# above). Without this, :TSUpdate / lazy.nvim's first-launch parser install fails
# with "ENOENT: no such file or directory (cmd): 'tree-sitter'".
echo "Installing tree-sitter CLI via npm..."
sudo npm install -g tree-sitter-cli

if ! command -v go &>/dev/null; then
    echo "Note: 'go' is not on PATH. Mason will skip gopls until Go is installed."
fi

echo "Neovim installation complete."
