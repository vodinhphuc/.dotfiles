#!/bin/bash
set -euo pipefail

# Oh My ZSH
OMZ_DIR="${HOME}/.oh-my-zsh"
if [ ! -d "$OMZ_DIR" ]; then
    echo "Installing oh-my-zsh..."
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "Already installed: oh-my-zsh"
fi

# Antigen (git.io is shut down — use direct GitHub URL)
if [ ! -f "${HOME}/.antigen.zsh" ]; then
    echo "Installing Antigen..."
    curl -fsSL https://raw.githubusercontent.com/zsh-users/antigen/master/bin/antigen.zsh > "${HOME}/.antigen.zsh"
else
    echo "Already installed: ~/.antigen.zsh"
fi

# Powerlevel10k theme
P10K_DIR="${HOME}/.oh-my-zsh/custom/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
    echo "Installing powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
else
    echo "Already installed: powerlevel10k"
fi

# Create oh-my-zsh completions cache dirs used by the docker plugin
# https://github.com/ohmyzsh/ohmyzsh/issues/11866
mkdir -p "${HOME}/.oh-my-zsh/cache/completions"
mkdir -p "${HOME}/.antigen/bundles/robbyrussell/oh-my-zsh/cache/completions"

# conda-zsh-completion plugin
CONDA_PLUGIN_DIR="${HOME}/.oh-my-zsh/custom/plugins/conda-zsh-completion"
if [ ! -d "$CONDA_PLUGIN_DIR" ]; then
    echo "Installing conda-zsh-completion..."
    git clone https://github.com/esc/conda-zsh-completion "$CONDA_PLUGIN_DIR"
else
    echo "Already installed: conda-zsh-completion"
fi
