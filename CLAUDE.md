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
4. `build_plan` discovers the two phases (`system update`, `base packages`) plus one entry per `scripts/programs/*.sh`. Defaults respect the target: programs in `NATIVE_ONLY_PROGRAMS` (`docker fan_control ibus_unikey nerd_font openrgb terminator visual_code`) start **deselected on WSL** (still visible/toggleable, tagged `(desktop/native)`)
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
| `neovim.sh` | Neovim (snap on native, official release tarball on WSL) + IDE deps + tree-sitter CLI (unprivileged, to `~/.npm-global`) |
| `nerd_font.sh` | JetBrainsMono Nerd Font to `~/.local/share/fonts` (no sudo). Override with `NERD_FONT_NAME`/`NERD_FONT_MATCH`. Terminal font + `have_nerd_font = true` stay manual |
| `openrgb.sh` | OpenRGB + i2c-tools; turns all RGB LEDs off now and via a boot-time systemd service (native-only). Per-device control: `.local/bin/rgb` / `docs/guides/rgb.md` |

| `openrgb.sh` | OpenRGB + i2c-tools; turns all RGB LEDs off now and via a boot-time systemd service (native-only) |

| `shellcheck.sh` | shellcheck (static analysis linter for the repo's shell scripts) |

| `terminator.sh` | Terminator. **Registers** itself as an `x-terminal-emulator` alternative (priority 50) but no longer claims the default — `wezterm.sh` does, at 60. Two scripts both forcing it would make the winner depend on `install.sh` ordering. Switch back with `update-alternatives --config x-terminal-emulator`. Caveat: this script rewrites `~/.config/terminator/config` unconditionally, so any background/font set through Terminator's GUI is lost on the next run |
| `tpm.sh` | Tmux Plugin Manager |
| `ttyd.sh` | ttyd web terminal as a systemd **user** service, bound to `tailscale0` (never `0.0.0.0`), attaching `tmux new -A -s dotfile`. Exists so Vietnamese can be typed from a tablet: Android terminal apps disable the keyboard's composing region, browsers do not. Hooks: `TTYD_PORT`/`TTYD_INTERFACE`/`TTYD_TMUX_SESSION`/`TTYD_CONFIG_DIR`/`TTYD_SYSTEMD_USER_DIR`, plus `TTYD_FORCE_PKG_INSTALLED`/`TTYD_SKIP_SYSTEMCTL` for tests. Reference: `docs/guides/ttyd.md` |
| `uv.sh` | uv + uvx (Python pkg/project manager), pre-generates zsh completions to `~/.config/uv` |
| `visual_code.sh` | VS Code (Microsoft apt repo — unconfined so ibus input methods work) |
| `wezterm.sh` | WezTerm (official apt repo), **native-only, installed alongside Terminator** — **the default terminal since 2026-08-22** — claims `x-terminal-emulator` at priority 60 and sets GNOME's `default-applications.terminal` to `/usr/bin/wezterm -e` (both are needed; Ctrl+Alt+T reads the gsettings, not the alternatives system). `/usr/bin/wezterm` is registered rather than the package's `open-wezterm-here`, which would feed a caller's `-e <cmd>` to exec as the program name. `WEZTERM_ALT_LINK` is a test hook so the suite does not depend on the machine's actual default. Opens maximized with `window_decorations = 'RESIZE'` (no title bar; `NONE` would break resizing) via a `gui-startup` handler that passes `cmd or {}` through so `wezterm start -- prog` still works; F11 toggles true fullscreen. Also creates `~/.config/wezterm/bg`, whose wallpapers **are committed** so they sync to other machines via `git pull`. Config is the stowed `.config/wezterm/wezterm.lua`: Catppuccin Mocha, JetBrainsMono Nerd Font, random background per window with `CTRL+SHIFT+b` to reshuffle, and an explicit `use_ime = true` plus a commented `enable_wayland = false` escape hatch — WezTerm speaks Wayland `zwp_text_input_v3` rather than GTK/VTE, so ibus/Vietnamese behaviour must be re-verified before making it the default terminal |

### `.local/bin/rgb`

Friendly per-device wrapper around OpenRGB (stowed onto `PATH`), companion to `scripts/programs/openrgb.sh`. Subcommands `list`/`status`/`colors`/`off`/`on`/`mode`/`persist` mirror the `.local/bin/fan` CLI style. Targets a device by index or case-insensitive name substring (omit = all); accepts named colors or 6-digit hex. `rgb persist on|off` toggles the `openrgb-off.service` boot service, and `on`/`mode` warn when that service will override the change at next boot. Testable via env hooks `OPENRGB_BIN`, `RGB_DRY_RUN=1`, `RGB_SUDO=` (unit-tested in `scripts/test_rgb_cli.sh`, dispatched from `test_programs.sh`). Full reference: `docs/guides/rgb.md`.

### `.local/bin/wallpaper`

Keeps the WezTerm background folder at the screen's resolution (stowed onto `PATH`), companion to `.config/wezterm/wezterm.lua`. Subcommands `list`/`check`/`normalize` mirror the `fan`/`rgb` CLI style. **Not** about how images look -- the Lua config already renders any aspect ratio correctly via `Cover`+`Center`+`NoRepeat` -- but about how big they are: an oversized JPEG must be decoded and pushed to the GPU on every `CTRL+SHIFT+b` switch, which is what makes the window blink, and these images are committed so they bloat the repo. Only images not already at the target are touched (so `normalize` is idempotent) and formats are preserved -- a PNG stays a PNG rather than being silently re-encoded. Originals are copied to `~/Downloads/wezterm-bg-originals` rather than committed, since committing them first would leave full-size blobs in git history permanently. Target resolution comes from `xrandr` (works under XWayland) and falls back to 1920x1080. `check` exits non-zero when work is pending, so it suits a pre-commit hook. Testable via env hooks `WALLPAPER_DIR`, `WALLPAPER_BACKUP_DIR`, `WALLPAPER_MAGICK`, `WALLPAPER_WIDTH`/`WALLPAPER_HEIGHT`, `WALLPAPER_DRY_RUN=1`, `WALLPAPER_QUALITY` (unit-tested in `scripts/test_wallpaper_cli.sh`, dispatched from `test_programs.sh`).

### `scripts/mount_disk.sh`

Standalone interactive utility (NOT in `programs/`, so `install.sh` never auto-runs it) to persistently mount a data partition to a folder. Safety-first: skips mounted/system/container (LUKS/LVM/RAID) volumes, treats desktop udisks auto-mounts (`/run/media`, `/media`) as transient and releases them before mounting, identifies disks by UUID, backs up `/etc/fstab` and uses `nofail` before test-mounting, and rolls back on any failure. Includes a **Filesystem** step: keep the existing filesystem (for NTFS, choose the `ntfs3` kernel driver [default] or `ntfs-3g`), or **reformat to ext4** — the only destructive path, gated by a typed `ERASE <dev>` confirmation and re-reading the new UUID after `mkfs`. `--dry-run` previews everything and is provably side-effect-free (all mutations are after the dry-run exit gate). Run `bash scripts/mount_disk.sh` (or `--dry-run`).

### `docs/troubleshooting/`

Incident post-mortems for hardware/OS problems that have actually happened on this machine — structured as triage commands → root-cause table → per-cause fix → lessons learned. Distinct from `docs/guides/` (how to *use* a tool). `nvidia-monitor-no-signal.md` covers a lost second monitor and its three known root causes (missing per-kernel NVIDIA module, bad cable, compositor state). Check here before debugging a recurring system symptom from scratch; `docs/troubleshooting/README.md` has the template for adding one.

### `.config/nvim/`

Kickstart.nvim, split into modules (2026-08-21) — `init.lua` is now ~95 lines and does four things: leader key, `require 'config.*'`, lazy.nvim bootstrap, and `{ import = 'plugins' }`. `lua/config/` holds `options`/`keymaps`/`diagnostics`/`autocmds`; `lua/plugins/` holds one file per concern (`lsp`, `telescope`, `completion`, `format`, `treesitter`, `editor`, `ui`, `markdown`, `practice`), each returning a lazy spec. **New plugin = new file in `lua/plugins/`** — lazy imports the directory, so nothing needs registering. The three customization anchors are file locations now, not search strings: LSP servers → `lua/plugins/lsp.lua`, parsers → `treesitter.lua`, formatters → `format.lua`. `~/.config/nvim` is a *directory* symlink, so new subdirectories go live without re-running `stow`. The split was verified behaviour-neutral by diffing a dump of the full plugin set, all 202 keymaps, options, diagnostics and autocmd groups before and after. Markdown reading is handled by two plugins added under the `<leader>m` which-key group: `render-markdown.nvim` (in-buffer styling, `<leader>mt` toggles it **globally** for the session) and `glow.nvim` (`<leader>mp` / `:Glow`, a floating glow pager). The glow spec overrides the plugin's own `Glow` command to set `CLICOLOR_FORCE=1` **around the spawn only** — glow.nvim pipes stdout rather than allocating a PTY, so glow otherwise emits no colour; exporting the var session-wide would force ANSI colour into ripgrep, git and the LSP servers. `<leader>tw` toggles `wrap`, because several tables in this repo exceed 200 columns and wrap into unreadable fragments. On a desktop session `init.lua` also switches the ibus input method off on `InsertLeave` and back on `InsertEnter`: a Vietnamese IME commits composed text as a **bracketed paste**, and nvim inserts pasted text in *any* mode, so Normal-mode keys otherwise land in the buffer instead of running commands. Guarded on ibus plus a display, so SSH and WSL are untouched (this now lives in `lua/config/autocmds.lua`). User-facing reference: `docs/guides/nvim.md`.

Two known gaps, deliberately not fixed during the split: `gd` is unbound (go-to-definition is `<C-]>` via `tagfunc`) and formatting has no keybinding — conform runs on save only.

### `.local/bin/fan`

Read/write wrapper over the raw hwmon `pwm` sysfs files (stowed onto `PATH`), companion to `scripts/programs/fan_control.sh`. Subcommands `list`/`status`/`set`/`manual`/`auto`. Only chips matching `^(nct6|it87|f71)` are considered controllable — `nvme`/`coretemp`/`acpitz` expose temps but no PWM and are filtered out. `set` takes a 0-100 percentage (mapped onto hwmon's 0-255 range) and always writes `pwm_enable=1` **before** the duty cycle, because a channel left in automatic mode has its value overwritten by the chip almost immediately; it refuses 0 without `--force`. Writes go direct when the sysfs file is writable and fall back to `sudo tee` otherwise, which is what lets `scripts/test_fan_cli.sh` drive it against a temp-dir fixture with no root. Testable via env hooks `HWMON_ROOT`, `FAN_DRY_RUN=1`, `FAN_SUDO=`. Full reference: `docs/guides/fans.md`.

## How to extend

**Add a program:** Create `scripts/programs/<name>.sh` with an idempotency guard. It is picked up automatically by `install.sh`. Add a matching test case to `scripts/test_programs.sh`, and make sure it passes `shellcheck -x` (the test suite enforces this).

**Add a dotfile:** Place the config file in the repo root at the path it should have relative to `~/`, then run `stow .`.

**Add a troubleshooting note:** Create `docs/troubleshooting/<symptom>.md` following the template in that folder's `README.md`, and link it from both `README.md` tables.

## Coding conventions

- **Every shell script MUST pass `shellcheck -x` with zero findings** (default severity — errors, warnings, info, and style). This is enforced by `scripts/test_programs.sh`, which fails the build on any finding. Run `shellcheck -x scripts/**/*.sh` before committing; fix issues rather than suppressing them. If a warning is a genuine false positive, silence it with a **targeted, commented** `# shellcheck disable=SCXXXX` on the specific line (never a blanket file-level or repo-level disable). Install it via `bash scripts/programs/shellcheck.sh`.
- All scripts: `#!/bin/bash` + `set -euo pipefail`
- Program scripts guard **each step**, never the whole script. A top-level `command -v X && exit 0` makes every step below it unreachable on an already-provisioned machine, so dependencies added later never install. This is not hypothetical: it silently blocked the tree-sitter CLI for months and left nvim-treesitter unable to compile any parser. Use `if ... else ... fi` per step, each printing `Already installed: <name>`
- Scripts are guarded with `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` only when they define reusable functions that tests source directly
- Tests mock `sudo`, `apt-get`, and external commands by prepending a `$BIN_DIR` to `PATH`; they never require network or root
- `.install_state`, `.install_errors`, and `.install.log` are gitignored runtime files
