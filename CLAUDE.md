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

# Run all tests (no sudo, no network) — includes the enforced shellcheck lint
bash scripts/test_programs.sh
bash scripts/test_orchestrator.sh

# Lint every script directly (must be clean before committing)
shellcheck -x scripts/*.sh scripts/programs/*.sh
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
5. Selection: `--all` accepts the target-aware defaults; an interactive TTY shows `select_menu` (↑/↓ or j/k to move, space to toggle, `a`/`n` all/none, `q` to abort, Enter to confirm); no TTY without `--all` errors out
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
| `openrgb.sh` | OpenRGB + i2c-tools; turns all RGB LEDs off now and via a boot-time systemd service (native-only) |

| `shellcheck.sh` | shellcheck (static analysis linter for the repo's shell scripts) |

| `terminator.sh` | Terminator, sets as default terminal (Ctrl+Alt+T) |
| `tpm.sh` | Tmux Plugin Manager |
| `uv.sh` | uv + uvx (Python pkg/project manager), pre-generates zsh completions to `~/.config/uv` |
| `visual_code.sh` | VS Code (Microsoft apt repo — unconfined so ibus input methods work) |

### `scripts/mount_disk.sh`

Standalone interactive utility (NOT in `programs/`, so `install.sh` never auto-runs it) to persistently mount a data partition to a folder. Safety-first: skips mounted/system/container (LUKS/LVM/RAID) volumes, treats desktop udisks auto-mounts (`/run/media`, `/media`) as transient and releases them before mounting, identifies disks by UUID, backs up `/etc/fstab` and uses `nofail` before test-mounting, and rolls back on any failure. Includes a **Filesystem** step: keep the existing filesystem (for NTFS, choose the `ntfs3` kernel driver [default] or `ntfs-3g`), or **reformat to ext4** — the only destructive path, gated by a typed `ERASE <dev>` confirmation and re-reading the new UUID after `mkfs`. `--dry-run` previews everything and is provably side-effect-free (all mutations are after the dry-run exit gate). Run `bash scripts/mount_disk.sh` (or `--dry-run`).

### `.config/nvim/init.lua`

Single-file kickstart.nvim config (the `lua/config/` + `lua/plugins/` split is specced but deliberately deferred — do not start it unprompted). Markdown reading is handled by two plugins added under the `<leader>m` which-key group: `render-markdown.nvim` (in-buffer styling, `<leader>mt` toggles it **globally** for the session) and `glow.nvim` (`<leader>mp` / `:Glow`, a floating glow pager). The glow spec overrides the plugin's own `Glow` command to set `CLICOLOR_FORCE=1` **around the spawn only** — glow.nvim pipes stdout rather than allocating a PTY, so glow otherwise emits no colour; exporting the var session-wide would force ANSI colour into ripgrep, git and the LSP servers. `<leader>tw` toggles `wrap`, because several tables in this repo exceed 200 columns and wrap into unreadable fragments. User-facing reference: `docs/guides/nvim.md`.

### `.local/bin/fan`

Read/write wrapper over the raw hwmon `pwm` sysfs files (stowed onto `PATH`), companion to `scripts/programs/fan_control.sh`. Subcommands `list`/`status`/`set`/`manual`/`auto`. Only chips matching `^(nct6|it87|f71)` are considered controllable — `nvme`/`coretemp`/`acpitz` expose temps but no PWM and are filtered out. `set` takes a 0-100 percentage (mapped onto hwmon's 0-255 range) and always writes `pwm_enable=1` **before** the duty cycle, because a channel left in automatic mode has its value overwritten by the chip almost immediately; it refuses 0 without `--force`. Writes go direct when the sysfs file is writable and fall back to `sudo tee` otherwise, which is what lets `scripts/test_fan_cli.sh` drive it against a temp-dir fixture with no root. Testable via env hooks `HWMON_ROOT`, `FAN_DRY_RUN=1`, `FAN_SUDO=`. Full reference: `docs/guides/fans.md`.

## How to extend

**Add a program:** Create `scripts/programs/<name>.sh` with an idempotency guard. It is picked up automatically by `install.sh`. Add a matching test case to `scripts/test_programs.sh`, and make sure it passes `shellcheck -x` (the test suite enforces this).

**Add a dotfile:** Place the config file in the repo root at the path it should have relative to `~/`, then run `stow .`.

## Coding conventions

- **Every shell script MUST pass `shellcheck -x` with zero findings** (default severity — errors, warnings, info, and style). This is enforced by `scripts/test_programs.sh`, which fails the build on any finding. Run `shellcheck -x scripts/**/*.sh` before committing; fix issues rather than suppressing them. If a warning is a genuine false positive, silence it with a **targeted, commented** `# shellcheck disable=SCXXXX` on the specific line (never a blanket file-level or repo-level disable). Install it via `bash scripts/programs/shellcheck.sh`.
- All scripts: `#!/bin/bash` + `set -euo pipefail`
- Scripts are guarded with `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` only when they define reusable functions that tests source directly
- Tests mock `sudo`, `apt-get`, and external commands by prepending a `$BIN_DIR` to `PATH`; they never require network or root
- `.install_state`, `.install_errors`, and `.install.log` are gitignored runtime files
