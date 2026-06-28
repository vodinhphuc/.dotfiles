#!/bin/bash
set -euo pipefail

# gh — GitHub CLI (pull requests, issues, repo ops from the terminal).
# Installed from GitHub's official apt repo so it runs unconfined and can read
# files inside hidden dirs like ~/.dotfiles/ (the snap is strictly confined).
if ! command -v gh &>/dev/null; then
    echo "Adding GitHub CLI apt repo..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
        sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
        sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update
    echo "Installing gh..."
    sudo apt-get install -y gh
else
    echo "Already installed: gh"
fi
