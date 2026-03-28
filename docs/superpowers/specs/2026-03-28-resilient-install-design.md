# Resilient Install Script Design

**Date:** 2026-03-28
**Scope:** Harden `scripts/install.sh` for resilience — idempotency, error isolation, resume capability, and clear failure reporting.

---

## Problem

The current `install.sh` has four failure modes:

1. **Not idempotent** — `mv ~/.bashrc ~/.bashrc.bk` fails on a second run; stow errors on pre-existing unmanaged files.
2. **No resume** — A failure mid-run leaves the system in a partial state with no way to continue from where it stopped.
3. **No error isolation** — A single program script failing (or calling `exit`) aborts all subsequent steps.
4. **No visibility** — No log, no summary, no record of what succeeded or failed.

---

## Approach: State-tracked orchestrator in pure bash

`install.sh` becomes an orchestrator that wraps each program script with state tracking and error isolation. No new runtime dependencies.

---

## Architecture

```
install.sh
  │
  ├── set -euo pipefail          # strict mode for orchestrator code
  ├── fix_system()               # always runs: apt update, stow (idempotent fixes)
  ├── install_base()             # always runs: apt install base packages
  └── for each scripts/programs/*.sh:
        └── run_step <name> <script>
              ├── already in .install_state? → print [SKIP], return
              ├── run script in subshell → log to .install.log
              ├── success? → append name to .install_state, print [OK]
              └── failure? → append name to .install_errors, print [FAIL], continue
  │
  └── print_summary()            # print table of OK/SKIP/FAIL, exit 1 if any failures
```

The individual scripts in `scripts/programs/` are **not modified** — all resilience logic lives in the orchestrator.

---

## State Files

All three files live in `~/.dotfiles/` and must be added to `.gitignore`.

| File | Purpose | Reset behavior |
|---|---|---|
| `.install_state` | One completed step name per line | Delete to force full re-run |
| `.install_errors` | Failed step names from last run | Overwritten each run |
| `.install.log` | Full stdout/stderr from all program scripts | Appended each run |

---

## Idempotency Fixes

### `~/.bashrc` backup
```bash
# Before (breaks on re-run):
mv ~/.bashrc ~/.bashrc.bk

# After (safe):
[ -f ~/.bashrc ] && [ ! -f ~/.bashrc.bk ] && mv ~/.bashrc ~/.bashrc.bk
```

### `stow .`
```bash
# Before (errors on pre-existing unmanaged files):
stow .

# After (adopts existing files, then restores repo versions):
stow --adopt . && git -C ~/.dotfiles checkout .
```

`fix_system()` is always re-run (not state-tracked) so stow symlinks always reflect the current repo.

---

## Error Isolation

Each program script runs in a `()` subshell. A `set -e` or bare `exit` inside a script cannot propagate to the orchestrator.

```bash
run_step() {
    local name=$1
    local script=$2

    if grep -qx "$name" ~/.dotfiles/.install_state 2>/dev/null; then
        echo "[SKIP] $name"
        return
    fi

    echo "[RUN] $name..."
    if (bash "$script" >> ~/.dotfiles/.install.log 2>&1); then
        echo "$name" >> ~/.dotfiles/.install_state
        echo "[OK]  $name"
    else
        echo "[FAIL] $name (see .install.log)"
        echo "$name" >> ~/.dotfiles/.install_errors
    fi
}
```

---

## Summary Report

Printed at the end of every run:

```
==========================================
  Install Summary
==========================================
  [OK]   stow / base packages
  [OK]   custome_zsh
  [OK]   docker
  [SKIP] miniconda (already installed)
  [FAIL] cloudflare-warp
  [SKIP] visual_code (already installed)
==========================================
  1 failed. Check ~/.dotfiles/.install.log
==========================================
```

Exit code `1` if any step failed, `0` if all steps passed or were skipped.

---

## Out of Scope

- Multi-distro support (Ubuntu only)
- Machine roles / profiles (dev vs. server)
- Dry-run mode
- Ansible or other external tooling
