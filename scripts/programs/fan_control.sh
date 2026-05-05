#!/bin/bash
set -euo pipefail

# Test hooks (overridable via env). Defaults match production paths.
MODULES_LOAD_DIR="${FAN_MODULES_LOAD_DIR:-/etc/modules-load.d}"
FORCE_PKG_INSTALLED="${FAN_FORCE_PKG_INSTALLED:-}"

pkg_installed() {
    local pkg="$1"
    if [ -n "$FORCE_PKG_INSTALLED" ]; then
        if [ "$FORCE_PKG_INSTALLED" = "1" ]; then return 0; else return 1; fi
    fi
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
}

if pkg_installed lm-sensors \
    && pkg_installed fancontrol \
    && [ -f "$MODULES_LOAD_DIR/nct6775.conf" ]; then
    echo "Already installed: fan_control"
    exit 0
fi

echo "Installing lm-sensors + fancontrol via apt..."
sudo apt-get install -y lm-sensors fancontrol

# nct6775 covers the Nuvoton NCT67xx family used on most modern Intel/AMD
# motherboards (incl. ASRock B660M Pro RS). If your board uses ITE (it87) or
# Fintek (f71*) instead, see docs/guides/fans.md.
echo "Loading nct6775 kernel module..."
sudo modprobe nct6775 || \
    echo "warning: 'modprobe nct6775' failed. Some boards need 'acpi_enforce_resources=lax' on the kernel cmdline. See docs/guides/fans.md."

echo "Persisting nct6775 across reboots..."
echo nct6775 | sudo tee "$MODULES_LOAD_DIR/nct6775.conf" >/dev/null

cat <<'EOF'

Next steps (interactive, must be run by you):

  1. sudo sensors-detect          # answer YES to Super-I/O probe; reboot when done
  2. sudo pwmconfig               # maps PWM channels to physical fans, writes /etc/fancontrol
  3. sudo systemctl enable --now fancontrol

Full walkthrough and safety notes: docs/guides/fans.md
EOF
