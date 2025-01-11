#!/bin/bash

if [ ! -f ~/antigen.zsh ]; then
    echo "Install Antigen..."
    curl -L git.io/antigen > ~/antigen.zsh
else
    echo "Already installed: ~/antigen.zsh"
fi
