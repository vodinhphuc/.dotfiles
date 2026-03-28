#!/bin/bash
set -euo pipefail

MINICONDA_DIR="${HOME}/miniconda3"

if [ ! -d "$MINICONDA_DIR" ]; then
    echo "Installing Miniconda3..."
    ARCH="$(uname -m)"
    INSTALLER="${MINICONDA_DIR}/miniconda.sh"
    mkdir -p "$MINICONDA_DIR"
    curl -fsSL "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${ARCH}.sh" -o "$INSTALLER"
    bash "$INSTALLER" -b -u -p "$MINICONDA_DIR"
    rm "$INSTALLER"
else
    echo "Already installed: miniconda3"
fi
