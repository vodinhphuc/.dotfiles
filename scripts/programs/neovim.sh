#!/bin/bash
set -euo pipefail

# Each step below guards itself. Do NOT add a script-wide `command -v nvim` early
# exit: it makes every step underneath unreachable on a machine that already has
# nvim, so dependencies added later never install. That regression left machines
# without the tree-sitter CLI, and nvim-treesitter failed to build every parser.

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
if command -v nvim &>/dev/null; then
    echo "Already installed: neovim"
elif [ "$ENVIRONMENT" = "wsl" ]; then
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

apt_deps=(ripgrep fd-find git build-essential unzip xclip nodejs npm)
missing_deps=()
for pkg in "${apt_deps[@]}"; do
    status="$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)"
    [ "$status" = "install ok installed" ] || missing_deps+=("$pkg")
done
if [ ${#missing_deps[@]} -eq 0 ]; then
    echo "Already installed: neovim runtime dependencies"
else
    echo "Installing Neovim runtime dependencies via apt: ${missing_deps[*]}"
    sudo apt-get install -y "${missing_deps[@]}"
fi

# nvim-treesitter (main branch, vendored in init.lua) builds parsers from source
# via the tree-sitter CLI. apt does not ship it; install via npm (just installed
# above). Without this, :TSUpdate / lazy.nvim's first-launch parser install fails
# with "ENOENT: no such file or directory (cmd): 'tree-sitter'".
#
# Installed unprivileged into ~/.npm-global rather than system-wide: `sudo npm
# install -g` leaves root-owned files under $HOME. .zshrc already puts that bin
# dir on PATH, but install.sh runs under bash, so prepend it here too.
NPM_PREFIX="$HOME/.npm-global"
export PATH="$NPM_PREFIX/bin:$PATH"
if command -v tree-sitter &>/dev/null; then
    echo "Already installed: tree-sitter CLI"
else
    echo "Installing tree-sitter CLI via npm..."
    npm install -g --prefix "$NPM_PREFIX" tree-sitter-cli
fi

if ! command -v go &>/dev/null; then
    echo "Note: 'go' is not on PATH. Mason will skip gopls until Go is installed."
fi

echo "Neovim installation complete."
