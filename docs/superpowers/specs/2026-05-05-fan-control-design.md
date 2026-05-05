# Fan Control — Design Spec

**Date:** 2026-05-05
**Status:** Approved (pending user spec review)
**Scope:** Motherboard / case / CPU fans on the user's desktop. GPU fans (RTX 3090) are explicitly out of scope.

---

## 1. Goal

Let the user control motherboard fan speeds from the command line on their Ubuntu desktop, with both:

- An automatic temperature-driven curve running by default (`fancontrol` daemon).
- A manual override workflow for one-shot adjustments.

Fits the existing dotfiles structure: idempotent installer in `scripts/programs/`, a stowed CLI wrapper, and a written user guide alongside `nvim.md`, `tmux.md`, `cli-readers.md`.

## 2. Hardware context

- Board: ASRock B660M Pro RS (Nuvoton Super-I/O, driven by the `nct6775` kernel module).
- CPU: x86_64.
- GPU: NVIDIA RTX 3090 — **not addressed by this spec.**
- Currently `/sys/class/hwmon/` exposes only `nvme`, `nvme`, `iwlwifi_1`, `coretemp`. No `pwm*` entries — the SIO chip's driver is not loaded yet, so Linux cannot touch the case/CPU fans until the installer runs.

## 3. Deliverables

Three artifacts:

1. `scripts/programs/fan_control.sh` — idempotent installer.
2. `.local/bin/fan` — CLI wrapper (stowed to `~/.local/bin/fan`, already on PATH).
3. `docs/guides/fans.md` — user guide.

Plus tests in `scripts/test_programs.sh` + a new `scripts/test_fan_cli.sh`, and a README update.

## 4. Component design

### 4.1 `scripts/programs/fan_control.sh`

Shape and conventions: matches existing scripts in `scripts/programs/` (`#!/bin/bash`, `set -euo pipefail`, idempotency guard with "Already installed: …" message).

Steps the script performs:

1. If `dpkg -l lm-sensors fancontrol` already shows both installed AND `/etc/modules-load.d/nct6775.conf` exists, print `"Already installed: fan_control"` and exit 0.
2. `sudo apt-get install -y lm-sensors fancontrol`.
3. `sudo modprobe nct6775` (best-effort — log a warning if it fails; some boards need `acpi_enforce_resources=lax`).
4. `echo nct6775 | sudo tee /etc/modules-load.d/nct6775.conf` to persist on reboot.
5. Print a clear "next steps" block pointing the user at `docs/guides/fans.md` for the interactive `sensors-detect` and `pwmconfig` steps.

Explicitly **not** done by the installer:

- `sensors-detect` — interactive, asks ~20 yes/no prompts, must be run by a human.
- `pwmconfig` — interactive, spins each fan up and down and asks the user to confirm which physical fan responded. Wiring varies per build; can't be safely automated.
- Adding `acpi_enforce_resources=lax` to the kernel cmdline — invasive, only some boards need it. Documented as a fallback in the guide.
- Committing `/etc/fancontrol` to the repo — paths and curves are personal/per-machine.

### 4.2 `.local/bin/fan`

Single bash script. Stowed via the existing GNU Stow setup: place at repo path `.local/bin/fan`, then `stow .` symlinks it to `~/.local/bin/fan` (which is already on PATH per the user's environment).

`set -euo pipefail`. Reads sysfs from a path determined by the `HWMON_ROOT` env var (defaults to `/sys/class/hwmon`) so the test harness can point it at a fake tree. Service operations are gated behind `FAN_DRY_RUN=1` (prints the `systemctl` command instead of running it) so tests don't need root.

#### Subcommands

| Command | Privilege | Behavior |
|---|---|---|
| `fan status` | none | Tabular output: chip name, fan label, RPM, temps, pwm channel, current PWM %, mode (auto/manual via `pwmN_enable`), and `fancontrol.service` state. |
| `fan list` | none | Lists controllable `pwmN` channels: `pwm1  /sys/class/hwmon/hwmonN/pwm1  (label if present)`. Skips chips that don't expose `pwm*` (nvme, coretemp, iwlwifi). |
| `fan set <pwmN> <0-100>` | needs root, self-elevates with `sudo` | Writes `1` to `pwmN_enable` (manual mode), then `round(pct × 255 / 100)` to `pwmN`. Refuses values outside 0–100. Refuses 0 unless `--force`. If `fancontrol.service` is active, prints a warning that the daemon will overwrite the value on its next tick. |
| `fan manual` | needs root, self-elevates | `systemctl stop fancontrol`. |
| `fan auto` | needs root, self-elevates | `systemctl start fancontrol`. |
| `fan -h` / `fan help` | none | Usage. |

#### Resolving `pwmN`

The user types `pwm1`, `pwm2`, etc. — these must be unambiguous across hwmon devices. The script enumerates hwmon dirs whose `name` is in an allowlist of "fan-controlling" chips (e.g. `nct6775`, `nct6798`, `it87`, `f71808e`) and refuses to operate on others. If the same `pwmN` appears under two such chips, exit with an error listing the full sysfs paths and asking the user to disambiguate. (For this user's hardware, only one such chip is expected.)

#### Self-elevation pattern

```bash
need_root() {
  if [[ $EUID -ne 0 ]]; then
    exec sudo --preserve-env=HWMON_ROOT,FAN_DRY_RUN "$0" "$@"
  fi
}
```

Called at the top of `set`, `manual`, `auto`. `status` and `list` never elevate.

#### Error contracts

- No PWM channels found: `error: no controllable fans detected. Did you run sensors-detect and reboot? See docs/guides/fans.md.` Exit 1.
- `fancontrol.service` not installed when `auto`/`manual` is invoked: `error: fancontrol is not configured yet. Run 'sudo pwmconfig' first; see docs/guides/fans.md.` Exit 1.
- Unknown pwm channel: print available channels (same as `fan list`), exit 1.
- Out-of-range or non-integer percentage: usage message, exit 1.

### 4.3 `docs/guides/fans.md`

Sections:

1. **What this controls** — motherboard / CPU / case fans only. GPU fans excluded; pointers to `nvidia-settings`, `nvfancontrol`, GreenWithEnvy for follow-up.
2. **Hardware detection** — running `sudo sensors-detect` once after install, what to answer (defaults are safe; YES to "probe Super-I/O" specifically), reboot required.
3. **Mapping fans (`pwmconfig`)** — interactive walkthrough, with safety warnings about the script forcing fans to 0% to identify them, and what to do if a fan doesn't restart afterwards (write `2` or `5` to `pwmN_enable` to return to BIOS/auto, or reboot).
4. **The fan curve (`/etc/fancontrol`)** — file format, INTERVAL/DEVNAME/MINTEMP/MAXTEMP/MINSTART/MINSTOP keys, an annotated example, `sudo systemctl restart fancontrol` after edits, `sudo systemctl enable fancontrol` for boot.
5. **Daily use** — the `fan` CLI, with a copy-pasteable example session.
6. **Safety** — never leave the CPU fan at 0%, always verify with `watch -n1 sensors` after curve changes, what to do if temps spike (`fan set <cpu_pwm> 100` then investigate).
7. **Troubleshooting** — no `pwm*` entries (try `acpi_enforce_resources=lax` on the kernel cmdline), `fancontrol` failing to start (read `journalctl -u fancontrol`), values not sticking (something else is writing pwm — check `pwmN_enable`).

## 5. Data flow

### Read (`fan status`, `fan list`)

```
/sys/class/hwmon/hwmon*/
  ├── name                  → identifies chip; skip if not in fan-controller allowlist
  ├── fan{N}_input          → RPM
  ├── fan{N}_label          → human label (optional)
  ├── temp{N}_input         → millidegrees C
  ├── temp{N}_label         → human label
  ├── pwm{N}                → raw 0-255
  └── pwm{N}_enable         → 0=off, 1=manual, 2/5=BIOS/auto
```

`fan status` prints one section per fan-controlling chip plus a final line with `systemctl is-active fancontrol`.

### Write (`fan set pwm1 60`)

1. Resolve `pwm1` → `$HWMON_ROOT/hwmonX/pwm1`.
2. If `systemctl is-active fancontrol` returns `active`: print `warning: fancontrol is running and will overwrite this on its next tick (~10s). Run 'fan manual' first to hold the value.` Continue anyway — the warning is enough.
3. `echo 1 | sudo tee $HWMON_ROOT/hwmonX/pwm1_enable >/dev/null`.
4. `echo 153 | sudo tee $HWMON_ROOT/hwmonX/pwm1 >/dev/null`  (60% of 255).

`set` is non-persistent across reboots by design — for permanent curves, the user edits `/etc/fancontrol`.

### Mode toggle

- `fan manual` = `systemctl stop fancontrol`. Fans hold last written PWM (or BIOS default if nothing has been written this boot).
- `fan auto` = `systemctl start fancontrol`. Daemon resumes the curve.

## 6. Testing

### 6.1 `scripts/programs/fan_control.sh` — covered by `scripts/test_programs.sh`

Add a new test case using the existing `$BIN_DIR`-on-PATH mocking pattern:

- Mock `sudo` (passthrough), `apt-get` (record args, succeed), `modprobe` (record args, succeed), `dpkg` (succeed/fail toggleable), `tee` (write to a temp file in the test dir).
- **First run:** packages-not-installed branch — assert apt was called with `install -y lm-sensors fancontrol`, modprobe was called with `nct6775`, and `/etc/modules-load.d/nct6775.conf` (redirected via the mocked `tee`) contains `nct6775`.
- **Second run:** packages-installed branch — assert no apt invocation and `"Already installed"` printed.

### 6.2 `.local/bin/fan` — new `scripts/test_fan_cli.sh`

Build a fake hwmon tree under a temp dir, set `HWMON_ROOT=$tmp` and `FAN_DRY_RUN=1`:

```
$tmp/
  hwmon0/{name=nct6798, fan1_input=1200, pwm1=128, pwm1_enable=2, temp1_input=42000, temp1_label=CPU}
  hwmon1/{name=nvme}                       # should be skipped
  hwmon2/{name=coretemp, temp1_input=...}  # should be skipped
```

Assertions:

- `fan list` lists exactly `pwm1` from `hwmon0`.
- `fan status` prints RPM 1200, temp 42°C, PWM 50%, mode auto.
- `fan set pwm1 60` writes `1` to `hwmon0/pwm1_enable` and `153` to `hwmon0/pwm1`.
- `fan set pwm1 0` exits non-zero; `fan set pwm1 0 --force` succeeds.
- `fan set pwm1 101` and `fan set pwm1 abc` exit non-zero with usage.
- `fan manual` / `fan auto` with `FAN_DRY_RUN=1` print the corresponding `systemctl` invocation and exit 0.
- `fan set pwm9` (unknown) prints available channels and exits non-zero.

`scripts/test_programs.sh` invokes `scripts/test_fan_cli.sh` so a single `bash scripts/test_programs.sh` covers everything.

## 7. File changes summary

| Path | Status | Purpose |
|---|---|---|
| `scripts/programs/fan_control.sh` | new | Idempotent installer |
| `.local/bin/fan` | new | CLI wrapper, stowed to `~/.local/bin/fan` |
| `docs/guides/fans.md` | new | User guide |
| `scripts/test_fan_cli.sh` | new | Unit tests for the CLI against a fake hwmon tree |
| `scripts/test_programs.sh` | edit | Add fan_control case; invoke `test_fan_cli.sh` |
| `README.md` | edit | Add fan control to installed-tools + user-guides sections |

## 8. Risks & non-goals

**Risks:**

- A wrong curve or a too-low manual override on the CPU fan can overheat the CPU. Mitigations: refuse-zero by default, guide warns to verify with `watch -n1 sensors` after every change, troubleshooting section gives the panic-button command (`fan set <pwm> 100`).
- `nct6775` may not bind on this exact board without `acpi_enforce_resources=lax` on the kernel cmdline. The installer does not modify GRUB; the guide documents this as a fallback.
- `pwmN` numbering is not guaranteed stable across kernel upgrades that change hwmon enumeration order. The CLI tolerates this by re-resolving on every invocation; the user's `/etc/fancontrol` may need updating after such changes (documented).

**Non-goals:**

- GPU fan control.
- Liquid-cooler control (`liquidctl`).
- A GUI / TUI.
- Committing the user's specific `/etc/fancontrol` curve to the repo.
- Automating the kernel cmdline change for `acpi_enforce_resources=lax`.
- Moving an existing user `~/.local/bin/fan` out of the way during stow (standard `stow --adopt` flow already handled by `scripts/install.sh`).
