#!/bin/bash

echo "Current working directory is: $(pwd)"
cwd=$(pwd)

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
echo "Current working directory is: $(pwd)"
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

echo "Current working directory is: $(pwd)"
echo "cd $cwd"
cd $cwd
echo "Current working directory is: $(pwd)"

# Run all scripts in programs/
chmod u+x scripts/programs/*
for f in scripts/programs/*.sh; do bash "$f" -H; done

# Get all upgrades
sudo apt upgrade -y
sudo apt autoremove -y

# Install Antigent
curl -L git.io/antigen > ~/antigen.zsh

echo "Intall powerlevel10k..."
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k

# config git
git config --global user.email "phucvd2512@gmail.com"
git config --global user.name "vodinhphuc"

