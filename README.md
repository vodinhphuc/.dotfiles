# dotfiles

Automated Ubuntu desktop environment setup using [GNU Stow](https://www.gnu.org/software/stow/) for dotfile management and idempotent shell scripts for program installation. Re-running on an existing machine is safe — every step skips if already done.

## What gets installed

| Category | Tools |
|---|---|
| Shell | zsh, oh-my-zsh, antigen, powerlevel10k, conda-zsh-completion |
| Terminal | Terminator (set as default Ctrl+Alt+T) |
| Editor | VS Code (snap) |
| Container | Docker (snap) |
| Python | Miniconda3 |
| Multiplexer | tmux + TPM (Tmux Plugin Manager) |
| Input method | ibus + ibus-unikey (Vietnamese input) |
| Utilities | curl, git, htop, tree, vim, wget, nvtop |

## Prerequisites

Fresh Ubuntu install with internet access. Nothing else required — the install script bootstraps everything.

## Quick start

### 1. Install git and configure it

```bash
sudo apt install -y git
git config --global user.name "your-name"
git config --global user.email "your@email.com"
```

### 2. Set up SSH key for GitHub

```bash
ssh-keygen -t ed25519 -C "your@email.com"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub   # paste this into https://github.com/settings/keys
```

### 3. Clone the repo

```bash
git clone git@github.com:vodinhphuc/.dotfiles.git ~/.dotfiles
```

### 4. Run the installer

```bash
cd ~/.dotfiles && bash scripts/install.sh
```

The installer will:
1. Run `apt update && apt full-upgrade`
2. Install `stow` and apply dotfile symlinks
3. Install base packages
4. Run every script in `scripts/programs/` in alphabetical order

Progress is saved in `.install_state`. If the installer is interrupted, re-run it — completed steps are skipped automatically.

### 5. Post-install steps

After the first run, a few things require manual action:

- **Reload shell** — open a new terminal or run `exec zsh` to load the zsh config
- **Docker group** — log out and back in for `docker` to work without `sudo`
- **Vietnamese input** — log out and back in, then use `Super+Space` to switch to Unikey
- **Powerlevel10k theme** — run `p10k configure` to set up the prompt style

## Resuming after failure

If a step fails it is logged but does not stop the rest of the install:

```bash
# See what failed
cat .install_errors

# See full output
cat .install.log

# Re-run — completed steps are skipped, failed steps are retried
bash scripts/install.sh
```

To force a specific step to re-run, remove its name from `.install_state`:

```bash
sed -i '/custome_zsh/d' .install_state
bash scripts/install.sh
```

## Repository structure

```
~/.dotfiles/
├── .antigenrc                  # zsh plugin list (antigen)
├── .p10k.zsh                   # powerlevel10k prompt config
├── .tmux.conf                  # tmux config
├── .zshrc                      # zsh config
└── scripts/
    ├── install.sh              # orchestrator
    ├── test_orchestrator.sh    # tests for install.sh logic
    ├── test_programs.sh        # idempotency tests for program scripts
    └── programs/
        ├── custome_zsh.sh      # oh-my-zsh, antigen, powerlevel10k
        ├── docker.sh           # Docker via snap
        ├── ibus_unikey.sh      # ibus + Vietnamese input setup
        ├── miniconda.sh        # Miniconda3
        ├── terminator.sh       # Terminator terminal emulator
        ├── tpm.sh              # Tmux Plugin Manager
        └── visual_code.sh      # VS Code via snap
```

Dotfiles in the repo root are symlinked into `~/` by `stow .`. Adding a new dotfile is two steps: place it in the repo at the correct relative path, then run `stow .`.

## Adding a new program

1. Create `scripts/programs/<name>.sh` with an idempotency guard:

```bash
#!/bin/bash
set -euo pipefail

if ! command -v <name> &>/dev/null; then
    echo "Installing <name>..."
    sudo apt-get install -y <name>
else
    echo "Already installed: <name>"
fi
```

2. Add a test case to `scripts/test_programs.sh`.

The script is picked up automatically by `install.sh` on next run.

## Running tests

Tests mock `sudo`, `apt-get`, and other external commands — no network or root required:

```bash
bash scripts/test_programs.sh
bash scripts/test_orchestrator.sh
```

## References

- [GNU Stow manual](https://www.gnu.org/software/stow/manual/stow.html)
- [oh-my-zsh](https://ohmyz.sh/)
- [powerlevel10k](https://github.com/romkatv/powerlevel10k)
- [antigen](https://github.com/zsh-users/antigen)
