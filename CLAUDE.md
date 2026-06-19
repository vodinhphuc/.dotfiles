# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repo does

Automates setting up a Ubuntu desktop environment. GNU Stow manages dotfile symlinks; shell scripts handle program installation.

## Key commands

```bash
# Full install (run from ~/.dotfiles on a fresh or existing machine)
bash scripts/install.sh

# Re-apply stow symlinks after adding a new dotfile
stow .

# Run a single program script in isolation
bash scripts/programs/<name>.sh

# Run all tests (no sudo, no network)
bash scripts/test_programs.sh
bash scripts/test_orchestrator.sh
```

## Architecture

### Stow symlinks

The repo root is a stow package. `stow .` creates symlinks in `~/` that mirror the repo's directory structure. `scripts/install.sh` runs `stow --adopt . && git checkout .` to handle pre-existing files without clobbering them.

### `scripts/install.sh`

Orchestrator. Runs once on a fresh machine (or resumes after failure):

1. Disable the install-media (`cdrom`) apt source so `apt update` can't break
2. `apt update && apt full-upgrade`
3. Install `stow`, apply symlinks
4. Install base packages (`zsh`, `curl`, `vim`, `tmux`, …)
5. Loop over `scripts/programs/*.sh`, running each via `run_step`

State is persisted in `.install_state` (completed steps), `.install_errors` (failed steps), and `.install.log` (full output). Re-running skips completed steps.

### `scripts/programs/`

Idempotent per-program scripts. Each script must:
- Guard with `command -v`, `dpkg -l`, or a directory existence check before installing
- Print `"Already installed: <name>"` when skipping
- Use `sudo apt-get install -y` or `sudo snap install`

Current scripts:

| Script | Installs |
|---|---|
| `custome_zsh.sh` | oh-my-zsh, antigen, powerlevel10k, conda-zsh-completion |
| `docker.sh` | Docker (snap), adds user to `docker` group |
| `fan_control.sh` | lm-sensors + fancontrol, persists `nct6775` kernel module |
| `glow.sh` | glow (Charm apt repo) + bat (markdown / syntax-highlighted reading) |
| `ibus_unikey.sh` | ibus, ibus-unikey, configures GNOME input sources |
| `miniconda.sh` | Miniconda3 to `~/miniconda3` |
| `neovim.sh` | Neovim (snap) + IDE deps + tree-sitter CLI |
| `terminator.sh` | Terminator, sets as default terminal (Ctrl+Alt+T) |
| `tpm.sh` | Tmux Plugin Manager |
| `uv.sh` | uv + uvx (Python pkg/project manager), pre-generates zsh completions to `~/.config/uv` |
| `visual_code.sh` | VS Code (snap) |

## How to extend

**Add a program:** Create `scripts/programs/<name>.sh` with an idempotency guard. It is picked up automatically by `install.sh`. Add a matching test case to `scripts/test_programs.sh`.

**Add a dotfile:** Place the config file in the repo root at the path it should have relative to `~/`, then run `stow .`.

## Coding conventions

- All scripts: `#!/bin/bash` + `set -euo pipefail`
- Scripts are guarded with `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` only when they define reusable functions that tests source directly
- Tests mock `sudo`, `apt-get`, and external commands by prepending a `$BIN_DIR` to `PATH`; they never require network or root
- `.install_state`, `.install_errors`, and `.install.log` are gitignored runtime files
