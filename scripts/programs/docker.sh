#!/bin/bash
set -euo pipefail

if ! command -v docker &>/dev/null; then
    echo "Installing Docker..."
    sudo snap install docker
    sudo usermod -aG docker "$USER"
    echo "Docker installed. Log out and back in for group membership to take effect."
else
    echo "Already installed: docker"
fi
