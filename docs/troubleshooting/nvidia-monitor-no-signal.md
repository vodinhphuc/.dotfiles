# One monitor has no signal (NVIDIA, dual-display)

A monitor goes dark — no signal, nothing on screen — while the other one keeps
working. On this machine (RTX 3090, `nvidia-driver-595-open`, Wayland/GNOME, two
DisplayPort monitors) this symptom has had **three different root causes**.
They look identical from the chair and have completely different fixes, so
**diagnose before touching anything**.

---

## Triage first — three commands

Run all three before forming any theory. Together they tell you which layer
broke.

```bash
# 1. Is the NVIDIA driver alive?
nvidia-smi

# 2. Which connectors are electrically connected?
for c in /sys/class/drm/card*-*/status; do
  echo "$(basename "$(dirname "$c")"): $(cat "$c")"
done

# 3. Which driver is actually bound to each card?
for d in /sys/class/drm/card[0-9]; do
  echo "$(basename "$d"): $(basename "$(readlink -f "$d/device/driver")")"
done
```

Read the results against this table:

| `nvidia-smi` | DRM connectors | `card0` driver | Root cause | Section |
|---|---|---|---|---|
| fails | NVIDIA ports absent entirely | `simple-framebuffer` | **Driver not loaded** — no kernel module for the running kernel | [A](#a-driver-not-loaded-missing-kernel-module) |
| works | all NVIDIA ports `disconnected`, no hotplug events | `nvidia` | **Physical** — cable / port / monitor input | [B](#b-physical-cable-port-or-input) |
| works | port `connected` but nothing displayed | `nvidia` | **Compositor** — output disabled or misplaced | [C](#c-compositor-output-disabled) |

The single most diagnostic line is **`card0: simple-framebuffer`**. That means
*no real GPU driver is running at all* — the picture you still see is the UEFI
boot framebuffer handed off at POST. It is a dumb single-output buffer, so it
can only paint the one display the BIOS lit up. That is exactly why one monitor
survives and the other is dead. See cause A.

---

## A. Driver not loaded (missing kernel module)

**Seen: 2026-07-02 (kernel 7.0.0-27), again 2026-08-10 (kernel 7.0.0-29).**

Ubuntu ships the NVIDIA kernel module as a **per-kernel-ABI binary package**:
`linux-modules-nvidia-595-open-<kernel>-generic`. When the kernel image upgrades
but that package does not follow, the running kernel has no `nvidia.ko` — the
card is left with nothing bound to it.

### Confirm it

```bash
uname -r                                    # running kernel
dpkg -l | grep linux-modules-nvidia         # newest module pkg — matches?
modinfo nvidia                              # "Module nvidia not found"
lspci -nnk | grep -A3 -i vga                # no "Kernel driver in use" line
```

The 2026-08-10 instance, verbatim:

```
uname -r                        → 7.0.0-29-generic
newest installed module pkg     → linux-modules-nvidia-595-open-7.0.0-28-generic
modinfo nvidia                  → Module nvidia not found
lspci 01:00.0 (RTX 3090)        → Kernel modules: nvidiafb, nouveau   (nothing in use)
card0                           → simple-framebuffer
card1 (i915 iGPU)               → all 6 connectors disconnected
```

The iGPU connectors reading `disconnected` is **correct and not the problem** —
both monitors are plugged into the 3090, so the Intel ports genuinely have
nothing on them. Don't chase that.

### Fix

```bash
sudo apt-get install -y \
  linux-modules-nvidia-595-open-$(uname -r) \
  linux-modules-nvidia-595-open-generic
sudo reboot
```

Install the **metapackage** (`...-open-generic`) too, not just the versioned
one. The metapackage is what pulls in the right module on every future kernel
bump; if it is pinned to an old ABI, this recurs at the next upgrade. Check it
with:

```bash
dpkg -l | grep linux-modules-nvidia-595-open-generic   # version should track uname -r
```

### Verify after reboot

```bash
nvidia-smi                                            # reports the 3090
for c in /sys/class/drm/card*-DP-*/status; do cat "$c"; done   # two "connected"
```

### Why it happens

The kernel image and the NVIDIA metapackage upgrade independently. A partial
`apt upgrade`, a phased/held-back update, or `apt upgrade` where the NVIDIA
package was deferred all leave the pair out of sync. Nothing warns you — the
machine boots fine and one monitor still lights up from the UEFI framebuffer.

### Prevention

Before rebooting after any kernel upgrade:

```bash
apt list --upgradable | grep -i nvidia    # nothing NVIDIA left behind?
dpkg -l | grep "linux-modules-nvidia.*$(uname -r)"   # module for the NEW kernel exists?
```

Watch for held-back packages in `apt upgrade` output — `linux-modules-nvidia-*`
being held back is the warning sign.

---

## B. Physical (cable, port, or input)

**Seen: 2026-07-09.**

Driver fully healthy — `nvidia-smi` works, module present for the running
kernel — but only one DisplayPort reads `connected` at the DRM level, every
other port reads `disconnected`, and there are **zero hotplug events in the
journal for this boot**.

### Confirm it

```bash
journalctl -b | grep -iE "hotplug|connector"
```

No hotplug events + healthy driver = the kernel never saw a monitor
*electrically* on that port. That is the physical layer. No amount of driver
reinstalling or compositor fiddling will fix it.

### Fix

Reseat or swap the display cables. In the 2026-07-09 case, swapping the cables
brought both monitors back — and the second display re-enumerated from `DP-4`
to `DP-5`, which is normal and harmless.

Also check, in order: the monitor's own input source (a monitor on the wrong
input looks exactly like "no signal"), the cable at both ends, a different port
on the GPU, and a known-good cable.

---

## C. Compositor (output disabled)

Driver healthy, the port reads `connected`, EDID is readable — but GNOME is not
lighting the output, or has parked it off-screen.

### Confirm and fix

```bash
# Wayland/GNOME
gnome-monitor-config list 2>/dev/null || journalctl -b --user -u gnome-shell | tail -40

# X11
xrandr --query
```

Then re-enable in **Settings → Displays**, or delete the stale layout and let
GNOME redetect:

```bash
mv ~/.config/monitors.xml ~/.config/monitors.xml.bak
# log out and back in
```

---

## Lessons learned

1. **Same symptom, different layers.** "Second monitor is dead" has meant a
   missing kernel module, a bad cable, and a compositor state bug on this
   machine. Running the three triage commands takes 15 seconds and rules out
   two of the three every time. Guessing has cost far more than that.

2. **`card0: simple-framebuffer` is the tell.** If you see it, stop looking at
   cables and displays — no GPU driver is loaded, full stop. The surviving
   monitor is being driven by UEFI, not by your graphics card.

3. **A working monitor is not evidence the driver works.** The UEFI framebuffer
   keeps one display alive with the GPU driver completely absent. Never infer
   "graphics are fine" from "I can see my desktop".

4. **Check what *should* be there, not just what errors.** `nvidia-smi` failing
   tells you something is wrong; comparing `uname -r` against the installed
   module packages tells you *what*. Absence of a package produces no error
   message anywhere.

5. **Disconnected iGPU connectors are a red herring** on a system where the
   monitors are on the discrete card. Always confirm which card owns the ports
   before reading anything into `disconnected`.

6. **Fix the metapackage, not just the instance.** Installing only the
   versioned module gets the monitor back today and guarantees a repeat at the
   next kernel bump. This exact regression has now happened twice.

---

## Machine reference

| | |
|---|---|
| Host | `homelab` |
| GPU | NVIDIA RTX 3090 (GA102), PCI `01:00.0` |
| Driver | `nvidia-driver-595-open` (595.71.05) |
| Session | Wayland / GNOME |
| Displays | 2 × 1920×1080 on the 3090's DisplayPort outputs (one rotated to portrait) |
| iGPU | Intel (`i915`) — present but no displays attached |
