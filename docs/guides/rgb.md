# RGB LEDs — OpenRGB + the `rgb` CLI

Reference for controlling motherboard/RAM/GPU RGB LEDs on this machine. OpenRGB
and the i2c plumbing are installed by `scripts/programs/openrgb.sh`; the `rgb`
command (`.local/bin/rgb`, stowed onto `PATH`) is a friendly per-device wrapper.

---

## What's installed

- **`openrgb`** (apt, not snap) — detects RGB controllers over the SMBus and sets
  colors/effects. The snap is strictly confined and cannot reach the i2c buses
  that the RAM and motherboard LEDs live on, so the apt build is used instead.
- **`i2c-tools`** + the `i2c-dev` and chipset SMBus modules (`i2c-i801` on Intel,
  `i2c-piix4` on AMD), persisted in `/etc/modules-load.d/openrgb.conf`.
- **`openrgb-off.service`** — a systemd oneshot that re-applies "all LEDs off" at
  every boot. This makes *off* the persistent default. Disable it (see
  [Persistence](#persistence)) if you'd rather your own colors survive reboots.

Native/desktop only — `openrgb.sh` is in `NATIVE_ONLY_PROGRAMS`, so it is
deselected on WSL (a guest has no hardware).

---

## `rgb` quick-start

```bash
rgb list                  # detected devices with their index and name
rgb status                # devices + whether the boot service forces off
rgb colors                # the named-color palette

rgb off                   # turn everything off
rgb on                    # turn everything on (defaults to white)
rgb on red                # everything red
rgb on ram blue           # just the RAM, blue
rgb on aura 1E90FF        # the "aura" device, a raw hex color
rgb mode rainbow          # rainbow effect on all devices

rgb persist off           # let your colors survive reboot
rgb persist on            # go back to always-off at boot
```

OpenRGB needs root for the RAM/motherboard SMBus, so `rgb` prefixes its calls
with `sudo` — expect a password prompt on the first mutating command.

---

## Targeting a device

The optional `target` in `off` / `on` / `mode` selects which controller to touch:

| Target | Meaning |
|---|---|
| *(omitted)* or `all` | every device |
| a number, e.g. `0`, `1` | the device at that index from `rgb list` |
| a name, e.g. `ram`, `aura` | case-insensitive **substring** of the device name |

A name that matches nothing, or matches more than one device, is an error that
prints the candidate list so you can be more specific.

---

## Colors

`COLOR` is a **name** or any **6-digit hex** (with or without a leading `#`, any
case). Run `rgb colors` to see the palette:

| Name | Hex | Name | Hex |
|---|---|---|---|
| `off` / `black` | `000000` | `cyan` | `00FFFF` |
| `white` | `FFFFFF` | `magenta` | `FF00FF` |
| `red` | `FF0000` | `orange` | `FF6000` |
| `green` | `00FF00` | `purple` | `8000FF` |
| `blue` | `0000FF` | `pink` | `FF3080` |
| `yellow` | `FFFF00` | `warm` | `FFB040` |

`rgb on` argument rules:

- **no args** → all devices, white
- **one arg** → if it's a known color it applies to **all** devices (`rgb on red`);
  otherwise it's the **target** with the default white (`rgb on ram`)
- **two args** → `target` then `COLOR` (`rgb on ram blue`)

---

## Persistence

Because `openrgb-off.service` reapplies *off* at every boot, any color you set by
hand is undone on the next reboot. `rgb on`/`rgb mode` print a note when the
service is enabled.

```bash
rgb persist off      # systemctl disable --now openrgb-off.service — colors stick
rgb persist on       # systemctl enable  --now openrgb-off.service — always off
rgb status           # shows the current service state
```

To remove the always-off behavior entirely (revert to firmware defaults):

```bash
sudo systemctl disable --now openrgb-off.service
sudo rm /etc/systemd/system/openrgb-off.service /etc/modules-load.d/openrgb.conf
sudo systemctl daemon-reload
```

---

## Troubleshooting

- **`rgb list` shows nothing / only USB devices.** The RAM and motherboard live
  on the SMBus, which needs the i2c modules and root. Confirm:
  ```bash
  sudo modprobe i2c-dev i2c-i801   # or i2c-piix4 on AMD
  sudo openrgb --list-devices
  ```
- **AMD boards: SMBus access denied.** Add `acpi_enforce_resources=lax` to the
  kernel command line (`/etc/default/grub` → `GRUB_CMDLINE_LINUX_DEFAULT`, then
  `sudo update-grub` and reboot).
- **Some LEDs stay lit no matter what.** They're firmware-controlled and OpenRGB
  can't touch them. Disable them in the BIOS/UEFI instead: ASUS *Aura Sync*,
  MSI *Mystic Light*, Gigabyte *RGB Fusion* → set to Off.

---

## Testing

`scripts/test_rgb_cli.sh` unit-tests the CLI against a fake `openrgb` binary
(no hardware, no root, no network). It uses the same env hooks the CLI exposes:

| Hook | Purpose |
|---|---|
| `OPENRGB_BIN` | path to the openrgb binary (a fake in tests) |
| `RGB_DRY_RUN=1` | print the openrgb/systemctl commands instead of running them |
| `RGB_SUDO=` | drop the `sudo` prefix |

Run it directly (`bash scripts/test_rgb_cli.sh`) or via `bash scripts/test_programs.sh`.
