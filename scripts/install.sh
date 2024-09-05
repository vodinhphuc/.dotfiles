#!/bin/bash

# Update Ubuntu and get standard repository programs
sudo apt update && sudo apt full-upgrade -y

function install {
  which $1 &> /dev/null

  if [ $? -ne 0 ]; then
    echo "Installing: ${1}..."
    sudo apt install -y $1
  else
    echo "Already installed: ${1}"
  fi
}

# Install dotfiles manager
install stow
# Create symlinks for config
cd ..
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
install zsh

# Run all scripts in programs/
for f in scripts/programs/*.sh; do bash "$f" -H; done

# Get all upgrades
sudo apt upgrade -y
sudo apt autoremove -y

# Install Ohmyzsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# config git
git config --global user.email "phucvd2512@gmail.com"
git config --global user.name "vodinhphuc"

