#!/bin/sh

# Oh My ZSH
if [ ! -d $ZSH ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "Already installed: oh-my-zsh"
fi

# Antigen
if [ ! -f ~/.antigen.zsh ]; then
    echo "Install Antigen..."
    curl -L git.io/antigen > ~/.antigen.zsh
    # Create cache and completions dir and add to $fpath to fix: https://github.com/ohmyzsh/ohmyzsh/issues/11866
    mkdir -p "$ZSH_CACHE_DIR/completions"
    (( ${fpath[(Ie)"$ZSH_CACHE_DIR/completions"]} )) || fpath=("$ZSH_CACHE_DIR/completions" $fpath)
else
    echo "Already installed: ~/.antigen.zsh"
fi

# Custom theme
if [ ! -d ~/.oh-my-zsh/custom/themes/powerlevel10k ]; then
    echo "Intall powerlevel10k..."
	git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k
else
	echo "Already installed: powerlevel10k"
fi

# Custom plugins
ZSH_CUSTOM=$ZSH/custom
if [ ! -d $ZSH_CUSTOM/plugins/conda-zsh-completion ]; then
    git clone https://github.com/esc/conda-zsh-completion
    mv conda-zsh-completion "$ZSH_CUSTOM/plugins/"
else
    echo "Already installed: $ZSH_CUSTOM/plugins/conda-zsh-completion"
fi
