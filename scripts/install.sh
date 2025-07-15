#!/bin/bash

echo "Current working directory is: $(pwd)"
cwd=$(pwd)

# Update Ubuntu and get standard repository programs
sudo apt update && sudo apt full-upgrade -y

function install {
    if ! command -v $1 &> /dev/null; then
        echo "Installing: ${1}..."
        sudo apt install -y $1
    else
        echo "Already installed: ${1}"
    fi
}

# Install dotfiles manager
install stow

# Create symlinks for config
cd ~/dotfiles
echo "Current working directory is: $(pwd)"
# move already ~/.bashrc to use customize file
mv ~/.bashrc ~/.bashrc.bk
stow .

# Basics
install chrome-gnome-shell
install curl
install git
install htop
install tree
install vim
install wget
install tmux

# use zsh
install zsh
chsh -s /usr/bin/zsh

install nvtop
install ibus-unikey

cd $cwd

# Run all scripts in programs/
chmod u+x scripts/programs/*.sh
for script in scripts/programs/*.sh; do
    bash "$script" -H
done

# Get all upgrades
sudo apt upgrade -y
sudo apt autoremove -y
