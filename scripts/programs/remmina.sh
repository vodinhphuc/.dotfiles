#!/bin/bash
set -euo pipefail

# Remmina — remote desktop client (RDP / VNC) with GNOME keyring integration.
# Installed from the Ubuntu archive, NOT the remmina-ppa-team/remmina-next PPA:
# that PPA lags new Ubuntu releases (it had no "resolute" build), and a PPA with
# no Release file makes every `apt update` fail. The archive tracks Remmina
# closely enough through -updates/-security.

# Test hooks (overridable via env). Defaults match production paths.
SOURCES_DIR="${REMMINA_SOURCES_DIR:-/etc/apt/sources.list.d}"

# Ubuntu's `remmina` only *recommends* its protocol plugins, so they are listed
# explicitly: a machine with Recommends disabled would otherwise get a client
# that cannot open RDP or VNC connections.
PACKAGES=(remmina remmina-plugin-rdp remmina-plugin-vnc remmina-plugin-secret)

pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

missing=()
for pkg in "${PACKAGES[@]}"; do
    if pkg_installed "$pkg"; then
        echo "Already installed: $pkg"
    else
        missing+=("$pkg")
    fi
done

if [ "${#missing[@]}" -gt 0 ]; then
    echo "Installing ${missing[*]}..."
    sudo apt-get install -y "${missing[@]}"
fi

# Warn rather than delete: removing an apt source is the user's call, but a
# stale remmina-next PPA is the usual reason `apt update` errors after an
# Ubuntu upgrade, so point straight at it.
shopt -s nullglob
stale=("$SOURCES_DIR"/*remmina-next*)
shopt -u nullglob
if [ "${#stale[@]}" -gt 0 ]; then
    echo "warning: remmina-next PPA source found: ${stale[*]}"
    echo "  It often has no build for the current Ubuntu release and breaks 'apt update'."
    echo "  Remove it with: sudo add-apt-repository --remove ppa:remmina-ppa-team/remmina-next"
fi
