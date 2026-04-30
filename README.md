# dotfiles

Automated Ubuntu desktop environment setup using [GNU Stow](https://www.gnu.org/software/stow/) for dotfile management and idempotent shell scripts for program installation. Re-running on an existing machine is safe — every step skips if already done.

## What gets installed

| Category | Tools |
|---|---|
| Shell | zsh, oh-my-zsh, antigen, powerlevel10k, conda-zsh-completion |
| Terminal | Terminator (set as default Ctrl+Alt+T) |
| Editors | Neovim (snap, kickstart-based IDE config), VS Code (snap), Vim |
| Container | Docker (snap) |
| Python | Miniconda3 |
| Multiplexer | tmux (prefix `Ctrl-q`) + TPM with catppuccin / tmux-yank / tmux-sensible plugins |
| Markdown / source reading | glow (Charm apt repo), bat (apt; aliased from `batcat`) |
| Input method | ibus + ibus-unikey (Vietnamese input) |
| Neovim runtime deps | ripgrep, fd-find, nodejs, npm, tree-sitter-cli, build-essential, xclip |
| Utilities | curl, git, htop, tree, wget, nvtop |

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
- **Neovim plugins** — first launch of `nvim` triggers lazy.nvim to install plugins (~30s) and Mason to install LSPs (background). Run `:checkhealth` once installs settle.
- **TPM plugins** — handled automatically by `scripts/programs/tpm.sh` (clones TPM, runs `install_plugins`). No `prefix + I` step needed.

## User guides

In-repo references for the daily-use tools (rendered with `glow`, paged with `less`):

| Guide | What it covers |
|---|---|
| [`docs/guides/nvim.md`](docs/guides/nvim.md) | Modes, leader keymaps, kickstart's LSP / Telescope / Mason / formatting, troubleshooting |
| [`docs/guides/tmux.md`](docs/guides/tmux.md) | Prefix (`Ctrl-q`), sessions / windows / panes, copy-paste with tmux-yank, plugin set, workflows |
| [`docs/guides/cli-readers.md`](docs/guides/cli-readers.md) | `glow` (markdown), `bat` (syntax-highlighted source) — quick-start + tmux notes |

Read any of them in the terminal:

```bash
glow ~/docs/guides/tmux.md
```

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
├── .bashrc                     # bash config (rarely used; zsh is primary)
├── .gitignore                  # gitignored runtime + machine-local state
├── .p10k.zsh                   # powerlevel10k prompt config
├── .stow-local-ignore          # files stow must NOT manage
├── .tmux.conf                  # tmux config (prefix Ctrl-q)
├── .zshrc                      # zsh config
├── .config/
│   └── nvim/
│       └── init.lua            # vendored kickstart.nvim + LSPs / formatters
├── docs/
│   ├── guides/                 # user-facing references (rendered with glow)
│   │   ├── nvim.md
│   │   ├── tmux.md
│   │   └── cli-readers.md
│   └── superpowers/            # design specs + implementation plans (process artifacts)
│       ├── specs/
│       └── plans/
└── scripts/
    ├── install.sh              # orchestrator
    ├── test_orchestrator.sh    # tests for install.sh logic
    ├── test_programs.sh        # idempotency tests for program scripts
    └── programs/
        ├── custome_zsh.sh      # oh-my-zsh, antigen, powerlevel10k
        ├── docker.sh           # Docker via snap
        ├── glow.sh             # glow + bat (markdown + syntax-highlighted reading)
        ├── ibus_unikey.sh      # ibus + Vietnamese input setup
        ├── miniconda.sh        # Miniconda3
        ├── neovim.sh           # Neovim (snap) + IDE deps + tree-sitter CLI
        ├── terminator.sh       # Terminator terminal emulator
        ├── tpm.sh              # Tmux Plugin Manager (auto-installs tmux plugins)
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
