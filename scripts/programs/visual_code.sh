#!/bin/bash
set -euo pipefail

if ! command -v code &>/dev/null; then
    echo "Installing Visual Studio Code..."
    sudo snap install --classic code
else
    echo "Already installed: visual studio code"
fi
