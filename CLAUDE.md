# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repo does

Automates setting up a Ubuntu desktop environment. GNU Stow manages dotfile symlinks; shell scripts handle program installation.

## Key commands

```bash
# Interactive install (run from ~/.dotfiles) — pick phases & programs from a menu
bash scripts/install.sh

# Non-interactive: install everything (required when there is no TTY, e.g. CI)
bash scripts/install.sh --all

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

1. Parse flags (`--all`/`-a` to skip the menu, `--native`/`--wsl` to force the target, `--help`/`-h`)
2. Disable the install-media (`cdrom`) apt source so `apt update` can't break
3. Resolve the install **target**: `detect_environment` returns `wsl` (when `$WSL_DISTRO_NAME` is set or `/proc/version` mentions microsoft) or `native`. `--native`/`--wsl` override; otherwise `choose_environment` prompts interactively. Sets `ENVIRONMENT`.
4. `build_plan` discovers the two phases (`system update`, `base packages`) plus one entry per `scripts/programs/*.sh`. Defaults respect the target: programs in `NATIVE_ONLY_PROGRAMS` (`docker fan_control ibus_unikey terminator visual_code`) start **deselected on WSL** (still visible/toggleable, tagged `(desktop/native)`)
5. Selection: `--all` accepts the target-aware defaults; an interactive TTY shows `select_menu` (toggle by number, `a`/`n`/`q`, Enter to confirm); no TTY without `--all` errors out
6. `apply_stow` (always) installs `stow` and applies symlinks
7. `run_plan` runs the selected phases (`system_update`, `install_base`) and programs (via `run_step`); `apt upgrade`/`autoremove` run only if `system update` was selected. `install_base` also skips `chrome-gnome-shell`/`nvtop` on WSL.

The selectable plan lives in the parallel arrays `ITEM_KEYS`/`ITEM_LABELS`/`ITEM_TYPES`/`ITEM_SCRIPTS`/`ITEM_ON`. State is persisted in `.install_state` (completed steps), `.install_errors` (failed steps), and `.install.log` (full output). Re-running skips completed steps.

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
| `gh.sh` | GitHub CLI (`gh`) from GitHub's official apt repo |
| `glow.sh` | glow (Charm apt repo) + bat (markdown / syntax-highlighted reading) |
| `ibus_unikey.sh` | ibus, ibus-unikey, configures GNOME input sources |
| `miniconda.sh` | Miniconda3 to `~/miniconda3` |
| `neovim.sh` | Neovim (snap on native, official release tarball on WSL) + IDE deps + tree-sitter CLI |
| `terminator.sh` | Terminator, sets as default terminal (Ctrl+Alt+T) |
| `tpm.sh` | Tmux Plugin Manager |
| `uv.sh` | uv + uvx (Python pkg/project manager), pre-generates zsh completions to `~/.config/uv` |
| `visual_code.sh` | VS Code (Microsoft apt repo — unconfined so ibus input methods work) |

## How to extend

**Add a program:** Create `scripts/programs/<name>.sh` with an idempotency guard. It is picked up automatically by `install.sh`. Add a matching test case to `scripts/test_programs.sh`.

**Add a dotfile:** Place the config file in the repo root at the path it should have relative to `~/`, then run `stow .`.

## Coding conventions

- All scripts: `#!/bin/bash` + `set -euo pipefail`
- Scripts are guarded with `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` only when they define reusable functions that tests source directly
- Tests mock `sudo`, `apt-get`, and external commands by prepending a `$BIN_DIR` to `PATH`; they never require network or root
- `.install_state`, `.install_errors`, and `.install.log` are gitignored runtime files
