#!/bin/bash
set -euo pipefail

# Docker Engine, installed from Docker's official apt repo.
#
# Why apt and not the snap (which this script used to install): the snap is
# strictly confined. It connects the `home` interface but not `removable-media`,
# so containers can bind-mount only from ~/ -- a data disk mounted at /data or
# /srv is invisible to every container. The snap's data-root cannot be moved off
# / either, so images pile up on the root filesystem. Neither is configurable;
# both are fatal for anything that stores real volume data. apt docker-ce reads
# /etc/docker/daemon.json, takes any data-root, and is unconfined.
#
# Test hooks (override to keep the suite off /etc and off the network):
#   DOCKER_APT_LIST  -- apt sources file       (default /etc/apt/sources.list.d/docker.list)
#   DOCKER_KEYRING   -- dearmoured signing key (default /etc/apt/keyrings/docker.asc)

DOCKER_APT_LIST="${DOCKER_APT_LIST:-/etc/apt/sources.list.d/docker.list}"
DOCKER_KEYRING="${DOCKER_KEYRING:-/etc/apt/keyrings/docker.asc}"

# A snap install satisfies `command -v docker`, so without this check the steps
# below would all report "already installed" and silently leave the confined
# version in place -- the exact regression this rewrite exists to prevent.
if command -v snap &>/dev/null && snap list docker &>/dev/null; then
    echo "WARNING: Docker is installed as a snap, which is strictly confined:"
    echo "  - containers can only bind-mount from \$HOME"
    echo "  - the image store cannot be moved off /"
    echo "Remove it first, then re-run this script:"
    echo "  sudo snap remove --purge docker    # destroys its images and volumes"
    exit 0
fi

# --- Step 1: Docker's apt repo ---
if [ ! -f "$DOCKER_APT_LIST" ]; then
    echo "Adding Docker apt repo..."
    sudo mkdir -p "$(dirname "$DOCKER_KEYRING")"
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$DOCKER_KEYRING"
    sudo chmod a+r "$DOCKER_KEYRING"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$DOCKER_KEYRING] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee "$DOCKER_APT_LIST" >/dev/null
    sudo apt-get update
else
    echo "Already installed: Docker apt repo"
fi

# --- Step 2: the engine, CLI, and the compose/buildx plugins ---
if ! command -v docker &>/dev/null; then
    echo "Installing Docker..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
else
    echo "Already installed: docker"
fi

# --- Step 3: docker group membership ---
# Guarded separately from step 2 on purpose. The previous version wrapped the
# install and the usermod in one `command -v docker` check, so on a machine that
# already had Docker the group was never added and every call needed sudo.
if id -nG "$USER" 2>/dev/null | grep -qw docker; then
    echo "Already installed: $USER in docker group"
else
    echo "Adding $USER to the docker group..."
    sudo groupadd -f docker
    sudo usermod -aG docker "$USER"
    echo "Log out and back in for group membership to take effect."
fi
