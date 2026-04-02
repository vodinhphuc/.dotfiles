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
