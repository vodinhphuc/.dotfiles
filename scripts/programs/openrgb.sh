#!/bin/bash
set -euo pipefail

# openrgb — detects RGB controllers (RAM, motherboard, GPU, ...) and turns every
# LED off, now and at every boot. Installed from apt (not snap): the snap is
# strictly confined and cannot reach the i2c/SMBus buses that the RAM and
# motherboard LEDs live on. Native/desktop only — a WSL guest has no hardware.

# Test hooks (overridable via env). Defaults match production paths.
MODULES_LOAD_DIR="${OPENRGB_MODULES_LOAD_DIR:-/etc/modules-load.d}"
SYSTEMD_DIR="${OPENRGB_SYSTEMD_DIR:-/etc/systemd/system}"
FORCE_PKG_INSTALLED="${OPENRGB_FORCE_PKG_INSTALLED:-}"

pkg_installed() {
    local pkg="$1"
    if [ -n "$FORCE_PKG_INSTALLED" ]; then
        if [ "$FORCE_PKG_INSTALLED" = "1" ]; then return 0; else return 1; fi
    fi
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
}

SERVICE_FILE="$SYSTEMD_DIR/openrgb-off.service"
MODULES_FILE="$MODULES_LOAD_DIR/openrgb.conf"

if pkg_installed openrgb \
    && [ -f "$SERVICE_FILE" ] \
    && [ -f "$MODULES_FILE" ]; then
    echo "Already installed: openrgb"
    exit 0
fi

echo "Installing openrgb + i2c-tools via apt..."
sudo apt-get install -y openrgb i2c-tools

# OpenRGB reaches RAM/motherboard controllers over the SMBus, exposed through
# i2c-dev plus the chipset's SMBus driver. i2c-i801 is Intel, i2c-piix4 is AMD;
# load whichever matches (harmless if the wrong one fails on this board).
CHIPSET_MODULE="i2c-i801"
if grep -q AuthenticAMD /proc/cpuinfo 2>/dev/null; then
    CHIPSET_MODULE="i2c-piix4"
fi

echo "Loading i2c modules (i2c-dev, $CHIPSET_MODULE)..."
sudo modprobe i2c-dev || \
    echo "warning: 'modprobe i2c-dev' failed; RAM/motherboard LEDs may be unreachable."
sudo modprobe "$CHIPSET_MODULE" || \
    echo "warning: 'modprobe $CHIPSET_MODULE' failed. AMD boards often need 'acpi_enforce_resources=lax' on the kernel cmdline for SMBus access."

echo "Persisting i2c modules across reboots..."
printf '%s\n%s\n' i2c-dev "$CHIPSET_MODULE" | sudo tee "$MODULES_FILE" >/dev/null

echo "Turning all LEDs off now..."
sudo openrgb --mode static --color 000000 || \
    echo "warning: OpenRGB found no controllers to set. Run 'sudo openrgb --list-devices' to debug."

echo "Installing openrgb-off systemd service (reapplies off at every boot)..."
sudo tee "$SERVICE_FILE" >/dev/null <<'EOF'
[Unit]
Description=Turn off all RGB LEDs via OpenRGB
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
# Devices are not always ready the instant the target is reached.
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/openrgb --mode static --color 000000

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now openrgb-off.service

cat <<'EOF'

Done. LEDs are off now and will be forced off at every boot.

If some LEDs are still lit, they are firmware-controlled and OpenRGB cannot
touch them — disable them in the BIOS/UEFI instead:
  ASUS   -> Aura Sync        (set to Off)
  MSI    -> Mystic Light     (set to Off)
  Gigabyte -> RGB Fusion     (set to Off)

Debug detected controllers with: sudo openrgb --list-devices
EOF
