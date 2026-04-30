#!/bin/bash
set -euo pipefail

# glow — terminal markdown renderer.
# Installed from Charm's apt repo (NOT snap) because the snap is published
# under strict confinement, which blocks reads of files inside hidden dirs
# like ~/.dotfiles/. The apt build runs unconfined and can read anywhere
# the user can.
if ! command -v glow &>/dev/null; then
    echo "Adding Charm apt repo..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | \
        sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | \
        sudo tee /etc/apt/sources.list.d/charm.list >/dev/null
    sudo apt-get update
    echo "Installing glow..."
    sudo apt-get install -y glow
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
