# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This repo automates setting up a Ubuntu environment using [GNU Stow](https://www.gnu.org/software/stow/) for symlink management and shell scripts for program installation.

## Setup Commands

```bash
# Full environment install (run from ~/.dotfiles)
bash scripts/install.sh

# Manually apply/refresh stow symlinks (from ~/.dotfiles)
stow .

# Run a single program install script
bash scripts/programs/<script>.sh
```

## Architecture

**Stow-managed dotfiles**: The repo root acts as a stow package. Running `stow .` from `~/.dotfiles` creates symlinks in `~/` mirroring the repo structure. Any config files added to the repo root will be symlinked to the home directory.

**`scripts/install.sh`**: Entry point. Runs `apt update/upgrade`, installs stow, runs `stow .`, installs base packages (zsh, curl, vim, tmux, etc.), then iterates over all `scripts/programs/*.sh` scripts.

**`scripts/programs/`**: Individual idempotent install scripts, each guarded with `command -v` or directory existence checks. Current scripts:
- `custome_zsh.sh` — oh-my-zsh, antigen, powerlevel10k theme, conda-zsh-completion plugin
- `docker.sh` — Docker via snap, adds user to docker group
- `miniconda.sh` — Miniconda3 to `~/miniconda3`
- `tpm.sh` — Tmux Plugin Manager to `~/.tmux/plugins/tpm`
- `terminator.sh` — writes Terminator terminal config
- `visual_code.sh` — VS Code via snap
- `cloudflare-warp.sh` — Cloudflare WARP client

## Adding New Programs

Create a new `scripts/programs/<name>.sh` with an idempotency guard (check if already installed before running). It will be picked up automatically by `install.sh`.

## Adding New Dotfiles

Place config files in the repo root mirroring the path relative to `~/`, then re-run `stow .` to create the symlink.
