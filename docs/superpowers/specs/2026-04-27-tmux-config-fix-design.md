# Tmux Config Fix — Design

**Date:** 2026-04-27
**Scope:** Minimal — fix existing bugs only; no new plugins, no theme changes.

## Goal

Make the tmux setup work end-to-end after `bash scripts/install.sh` on a fresh machine, with no manual `prefix + I` step required.

## Problem

Today, `.tmux.conf` declares plugins using the wrong directive name (`@plugins` plural) and several wrong GitHub paths. As a result, only `catppuccin/tmux` actually loads. `tmux-yank`, `tmux-sensible`, and `vim-tmux-navigator` are silently skipped by TPM.

Additionally, even when the directives are correct, `scripts/programs/tpm.sh` only clones TPM; the user must launch tmux and press `prefix + I` manually to install plugins. This breaks the "one command sets everything up" promise of the dotfiles installer.

## Decisions

1. **Drop `vim-tmux-navigator`.** The matching vim-side plugin is not installed in `.vimrc` and there is no vim plugin manager configured. Enabling only the tmux half ships a half-broken feature. Re-add later if/when a vim plugin manager is introduced.
2. **Drop the `tmux-plugins/tpm` plugin declaration.** TPM is the manager, loaded by the existing `run '~/.tmux/plugins/tpm/tpm'` line at the bottom of the config. It does not need to be listed as a plugin.
3. **Auto-install plugins via `tpm.sh`,** not via a self-bootstrap snippet inside `.tmux.conf`. Keeps the dotfiles philosophy of "program scripts own installation; configs own runtime behavior."

Final active plugin set: `catppuccin/tmux`, `tmux-plugins/tmux-yank`, `tmux-plugins/tmux-sensible`.

## Changes

### `.tmux.conf`

| Line | Before | After |
|---|---|---|
| 29 | `set -g @plugins 'tmux/plugins/tmux-yank'` | `set -g @plugin 'tmux-plugins/tmux-yank'` |
| 40 | `set -g @plugins 'tmux-plugins/tpm'` | *(delete)* |
| 41 | `set -g @plugins 'tmux-plugins/tmux/sensible'` | `set -g @plugin 'tmux-plugins/tmux-sensible'` |
| 42 | `set -g @plugins 'christoomey/vim-tmux-navigator'` | *(delete)* |

Line 24 (`set -g @plugin 'catppuccin/tmux'`) is already correct. No other lines change.

### `scripts/programs/tpm.sh`

Extend the existing script to invoke TPM's `install_plugins` after cloning:

```bash
#!/bin/bash
set -euo pipefail

TPM_DIR="${HOME}/.tmux/plugins/tpm"

if [ ! -d "$TPM_DIR" ]; then
    echo "Installing Tmux Plugin Manager..."
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
    echo "Already installed: $TPM_DIR"
fi

# Install/update plugins listed in ~/.tmux.conf (idempotent)
if [ -x "$TPM_DIR/bin/install_plugins" ]; then
    echo "Installing tmux plugins from .tmux.conf..."
    "$TPM_DIR/bin/install_plugins"
fi
```

`install_plugins` is idempotent — re-running it on already-installed plugins is a no-op. It reads `~/.tmux.conf`, which the orchestrator has already symlinked via `stow .` before `programs/*.sh` runs.

## Error handling

- The `[ -x "$TPM_DIR/bin/install_plugins" ]` guard prevents breakage if TPM's layout ever changes upstream.
- `set -euo pipefail` aborts on `git clone` failure; orchestrator records that in `.install_errors`.
- If `~/.tmux.conf` is missing (e.g. someone runs `tpm.sh` standalone without stowing), `install_plugins` exits non-zero. We accept this as a fail-loud signal — running program scripts out of order is a user error and should not be silently tolerated.

## Testing

### Automated

Update `scripts/test_programs.sh` to add a tpm test case that:
- Stubs `git` so cloning is a no-op (mirrors the existing `$BIN_DIR` PATH-prepend mocking pattern).
- Provides a fake `$HOME/.tmux/plugins/tpm/bin/install_plugins` executable that records its invocation.
- Asserts both git clone and install_plugins are called once on a fresh run.
- Asserts the second run prints "Already installed" and still re-runs install_plugins (which a real binary handles idempotently).

### Manual verification

On a working machine:
1. `bash scripts/programs/tpm.sh` — expect plugin install output, no errors.
2. `bash scripts/programs/tpm.sh` — expect "Already installed" plus a quiet plugin install pass.
3. Launch tmux, confirm:
   - Catppuccin status bar appears (already worked before; should still work).
   - In copy-mode, `v` selects, `y` copies, and the selected text is pasteable into a browser/VS Code via Ctrl+V (proves tmux-yank loaded).
   - `prefix + R` reloads the config with a "Reloaded!" message (proves tmux-sensible loaded).
4. `git status` — confirm `.install_state` and `.install_errors` reflect a clean run.

## Out of scope

- New plugins (tmux-resurrect, tmux-fzf, etc.) — explicitly excluded by the chosen "minimal" scope.
- Restoring `vim-tmux-navigator` — requires introducing a vim plugin manager; tracked as a separate future task.
- Status bar styling, keybind ergonomics, history-limit tweaks — partially covered by tmux-sensible defaults; further customization is a separate spec.
