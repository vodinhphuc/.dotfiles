#!/bin/bash
set -euo pipefail

# fzf — general-purpose fuzzy finder, wired into zsh for Ctrl-T (files),
# Ctrl-R (history), Alt-C (cd) and ** <TAB> completion.
#
# Installed from apt rather than upstream's git clone. Ubuntu 26.04 ships 0.67,
# well past the 0.48 that introduced `fzf --zsh`, and the git-clone installer
# insists on appending its own lines to ~/.zshrc — which is a stow symlink into
# this repo, so it would either fail or fight the repo on every run.

# Test hooks (overridable via env). Defaults match production paths.
CONFIG_DIR="${FZF_CONFIG_DIR:-$HOME/.config/fzf}"
EXAMPLES_DIR="${FZF_EXAMPLES_DIR:-/usr/share/doc/fzf/examples}"

if ! command -v fzf &>/dev/null; then
    echo "Installing fzf..."
    sudo apt-get install -y fzf
else
    echo "Already installed: fzf"
fi

# fd backs FZF_DEFAULT_COMMAND (see .zshrc): it honours .gitignore and skips
# .git, which plain `find` does not. Ubuntu names the binary `fdfind` because
# the name `fd` is already taken by an unrelated package.
if ! command -v fdfind &>/dev/null; then
    echo "Installing fd-find..."
    sudo apt-get install -y fd-find
else
    echo "Already installed: fd-find"
fi

# Write the zsh integration (key bindings + completion) to a static file so
# .zshrc can source it instead of running `fzf --zsh` on every shell start —
# the same trick uv.sh uses for its completions. Deliberately unguarded: it is
# regenerated on every run so it tracks the installed fzf across upgrades.
generate_integration() {
    local out="$1"
    if fzf --zsh > "$out" 2>/dev/null && [ -s "$out" ]; then
        return 0
    fi
    # fzf < 0.48 has no --zsh; Debian/Ubuntu ship the same snippets as files.
    : > "$out"
    local found=1 snippet
    for snippet in key-bindings.zsh completion.zsh; do
        if [ -f "$EXAMPLES_DIR/$snippet" ]; then
            cat "$EXAMPLES_DIR/$snippet" >> "$out"
            found=0
        fi
    done
    return "$found"
}

mkdir -p "$CONFIG_DIR"
# Generated beside the target rather than in /tmp, so the install is one atomic
# rename: a failed regeneration leaves the previous working file untouched
# instead of truncating it (the mistake terminator.sh used to make).
TMP_INTEGRATION="$CONFIG_DIR/.fzf.zsh.tmp"
if generate_integration "$TMP_INTEGRATION"; then
    chmod 644 "$TMP_INTEGRATION"
    mv "$TMP_INTEGRATION" "$CONFIG_DIR/fzf.zsh"
    echo "Generated fzf zsh integration in $CONFIG_DIR/fzf.zsh"
else
    rm -f "$TMP_INTEGRATION"
    echo "Warning: could not generate the fzf zsh integration" >&2
    echo "         (needs 'fzf --zsh' or snippets in $EXAMPLES_DIR)" >&2
fi
