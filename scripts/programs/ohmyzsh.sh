#!/bin/sh

if [ ! -d $ZSH ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "Already installed: oh-my-zsh"
fi

