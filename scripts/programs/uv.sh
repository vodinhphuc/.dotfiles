#!/bin/bash
set -euo pipefail

# uv — fast Python package & project manager (replaces pip/pip-tools/virtualenv).
# Installed via Astral's official standalone installer, which drops uv + uvx into
# ~/.local/bin (already on PATH via .zshrc). UV_NO_MODIFY_PATH=1 stops the
# installer from appending its own PATH lines to the stow-managed shell rc files.
if ! command -v uv &>/dev/null; then
    echo "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
    # The fresh install lands in ~/.local/bin; make it visible to the rest of
    # this script without waiting for a new shell to reload PATH.
    export PATH="${HOME}/.local/bin:${PATH}"
else
    echo "Already installed: uv"
fi

# Pre-generate zsh completion scripts so .zshrc can source static files instead
# of spawning `uv`/`uvx` on every shell startup. Regenerated on each run so they
# stay current after `uv self update`. Lives outside the repo (generated, version-tied).
COMPLETION_DIR="${HOME}/.config/uv"
mkdir -p "$COMPLETION_DIR"
uv generate-shell-completion zsh > "$COMPLETION_DIR/uv.zsh"
uvx --generate-shell-completion zsh > "$COMPLETION_DIR/uvx.zsh"
echo "Generated uv/uvx zsh completions in $COMPLETION_DIR"
