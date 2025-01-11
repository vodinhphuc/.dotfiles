#!/bin/bash

if [ ! -f ~/antigen.zsh ]; then
    echo "Install Antigen..."
    curl -L git.io/antigen > ~/antigen.zsh
else
    echo "Already installed: ~/antigen.zsh"
fi

if [ ! -d ~/.oh-my-zsh/custom/themes/powerlevel10k ]; then
    echo "Intall powerlevel10k..."
	git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k
else
	echo "Already installed: powerlevel10k"
fi

