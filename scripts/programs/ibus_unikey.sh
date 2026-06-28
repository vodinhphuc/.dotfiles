#!/bin/bash
set -euo pipefail

# Install ibus and ibus-unikey
if ! dpkg -l ibus-unikey 2>/dev/null | grep -q "^ii"; then
    echo "Installing ibus-unikey..."
    sudo apt-get install -y ibus ibus-unikey
else
    echo "Already installed: ibus-unikey"
fi

# Set ibus as the system input method framework
im-config -n ibus

# Persist IM module env vars so all toolkits use ibus — notably GTK_IM_MODULE,
# which Chromium/Electron apps (VS Code) need to receive ibus input under XWayland.
for kv in "GTK_IM_MODULE=ibus" "QT_IM_MODULE=ibus" "XMODIFIERS=@im=ibus"; do
    key=${kv%%=*}
    if grep -q "^${key}=" /etc/environment; then
        echo "Already configured: ${key} in /etc/environment"
    else
        echo "Adding ${kv} to /etc/environment..."
        echo "$kv" | sudo tee -a /etc/environment >/dev/null
    fi
done

# Add Unikey to GNOME input sources (keeps existing 'us' keyboard)
current=$(gsettings get org.gnome.desktop.input-sources sources)
if echo "$current" | grep -q "Unikey"; then
    echo "Already configured: Unikey input source"
else
    echo "Adding Unikey to GNOME input sources..."
    gsettings set org.gnome.desktop.input-sources sources \
        "[('xkb', 'us'), ('ibus', 'Unikey')]"
fi

# Restart ibus to apply changes
ibus restart 2>/dev/null || true
echo "ibus-unikey setup complete. Log out and back in to activate."
