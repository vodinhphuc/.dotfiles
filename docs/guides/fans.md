# Fan Control — `fan` + `fancontrol`

Controlling case and CPU fan speeds on Linux, and the `fan` CLI that wraps it.

Two layers are involved, and it helps to keep them straight:

- **`fancontrol`** is a daemon shipped with `lm-sensors`. It reads a curve from
  `/etc/fancontrol` and continuously adjusts PWM duty cycles based on temperature.
  This is what you want running day to day.
- **`fan`** (this repo, `.local/bin/fan`, stowed onto `PATH`) is a thin read/write
  wrapper over the raw sysfs `pwm` files. Use it to inspect what the kernel sees and
  to override a fan by hand, usually while tuning or debugging.

They fight if you use them at the same time — see [Manual vs. automatic](#manual-vs-automatic).

---

## What's installed

`scripts/programs/fan_control.sh` (native-only; deselected on WSL) installs:

| Piece | Why |
|---|---|
| `lm-sensors` | `sensors`, `sensors-detect`, the hwmon userspace |
| `fancontrol` | the curve daemon plus `pwmconfig` |
| `nct6775` kernel module | exposes the Super-I/O chip's fan/PWM channels, persisted via `/etc/modules-load.d/nct6775.conf` |

`nct6775` covers the Nuvoton NCT67xx family used on most modern Intel/AMD boards. If
yours is ITE or Fintek instead, the module is `it87` or `f71882fg` — the `fan` CLI
already recognises all three chip families.

---

## First-time setup

The install script stops short of the interactive steps on purpose — they ask
hardware questions only you can answer, and one of them spins your fans up and down.

```bash
bash scripts/programs/fan_control.sh   # packages + module (safe, idempotent)

sudo sensors-detect                    # answer YES to the Super-I/O probe; reboot after
sudo pwmconfig                         # maps each PWM channel to a physical fan
sudo systemctl enable --now fancontrol
```

**`pwmconfig` stops each fan in turn** to work out which PWM controls which tachometer.
That is normal, but do not run it under load — your CPU is briefly uncooled. Close
anything heavy first, and let it finish rather than killing it halfway, or a fan can be
left at a stopped duty cycle.

`pwmconfig` writes `/etc/fancontrol`. That file is the curve; edit it to retune.

---

## `fan` quick-start

```bash
fan list              # controllable PWM channels, with labels and sysfs paths
fan status            # fans (RPM), temps (°C), PWM duty + mode, service state
fan set pwm1 60       # set channel to 60% -- switches it to manual
fan set pwm1 0 --force
fan manual            # stop fancontrol so manual values stick
fan auto              # start fancontrol; the curve takes back over
fan -h
```

Typical `fan status` output:

```
Chip: nct6798  (/sys/class/hwmon/hwmon0)
  fan1   CPU_FAN        1200 RPM
  temp1  CPU              42 C
  pwm1                    50% (128/255)  mode: auto

fancontrol service: active
```

**Percentages are the CLI's unit; sysfs uses 0–255.** `fan set pwm1 60` writes
`153` (60% of 255). `fan status` converts back the other way, so the number you set is
the number you see.

### Modes

The `mode:` column is the kernel's `pwm_enable` value:

| Value | Shown as | Meaning |
|---|---|---|
| `0` | `full-speed` | no control — the fan runs flat out |
| `1` | `manual` | duty cycle is whatever was last written |
| `2` | `auto` | the chip's own curve is driving it (what `fancontrol` sets up) |

`fan set` always switches the channel to `manual` first, because writing a duty cycle
to a channel still in `auto` gets overwritten by the chip almost immediately.

---

## Manual vs. automatic

This is the part that confuses people, so it's worth stating plainly:

**`fancontrol` will undo your manual changes within a second or two.** It runs a loop,
and every iteration it rewrites the PWM values from its curve. `fan set` changes the
mode to manual, but the daemon simply sets it back.

So the tuning workflow is:

```bash
fan manual            # stop the daemon
fan set pwm1 40       # now this sticks
fan status            # verify RPM actually moved
fan auto              # hand control back when you're done
```

Forgetting `fan auto` leaves your fans pinned wherever you left them, with no thermal
response at all. If you're unsure what state you're in, `fan status` shows both the
per-channel mode and whether the service is active.

---

## Safety notes

- **0% stops the fan completely.** `fan set` refuses it unless you pass `--force`, and
  that guard exists for a reason. A stopped CPU fan will thermally throttle and can
  shut the machine down; a stopped GPU or case fan is quieter about it and just cooks
  the components.
- **Don't tune under load.** Set your curve while idle, then stress-test and watch
  `fan status`, rather than the other way round.
- **A reboot resets everything.** Manual values live in sysfs only. `fancontrol`
  restarts from `/etc/fancontrol`, so persistent changes belong in that file.
- **`fan` needs root to write.** It writes directly when the sysfs file is writable and
  falls back to `sudo tee` otherwise, so you'll be prompted on a normal system.

---

## Troubleshooting

| Symptom | First thing to try |
|---|---|
| `No controllable fan chips found` | The Super-I/O module isn't loaded. `lsmod \| grep nct6775`, then `sudo modprobe nct6775`. If it isn't installed, run `scripts/programs/fan_control.sh`. |
| `modprobe nct6775` fails | Some boards need `acpi_enforce_resources=lax` on the kernel command line. Add it in `/etc/default/grub`, `sudo update-grub`, reboot. |
| Module loads but no `pwm*` files | Your board is ITE or Fintek, not Nuvoton. Try `sudo modprobe it87` or `f71882fg`. `fan` recognises all three. |
| `sensors` shows temps but `fan list` is empty | Those chips (`nvme`, `coretemp`, `acpitz`) only report temperature — they have no PWM to control. `fan` filters them out deliberately. |
| Manual speed snaps back instantly | `fancontrol` is running. `fan manual` first. |
| Fans at full speed after a crash | A channel is stuck in `mode: full-speed` (`pwm_enable=0`). `fan auto`, or `fan set pwmN <pct>` to take manual control. |

---

## Environment hooks

Mostly for the test suite, but useful for dry runs:

| Variable | Effect |
|---|---|
| `HWMON_ROOT` | Point at a different sysfs root (default `/sys/class/hwmon`) |
| `FAN_DRY_RUN=1` | Print `systemctl` commands instead of running them |
| `FAN_SUDO=` | Drop the `sudo` prefix (already-root shells, tests) |

`scripts/test_fan_cli.sh` uses all three to exercise the CLI against a fake hwmon tree
— no root, no real hardware. Run it directly, or via `scripts/test_programs.sh`.

---

## See also

- `sensors` — one-shot reading of every hwmon sensor
- `watch -n1 sensors` — live view while stress-testing
- `/etc/fancontrol` — the curve itself; `man 5 fancontrol` documents the format
