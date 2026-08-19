#!/bin/bash
set -euo pipefail

# ttyd — serves a terminal over HTTP so it can be reached from a browser.
#
# The reason this exists is input, not convenience. Android terminal apps
# (Termius, Termux alike) declare their input field as "raw, no suggestions",
# and both Gboard and Samsung Keyboard respond by switching off the composing
# region — which is exactly what Vietnamese Telex needs. Browser text fields
# still compose normally, so a browser-based terminal is a way back to typing
# Vietnamese into a session running on this machine.
#
# It attaches to the same tmux session as an SSH client would, so the browser
# and a terminal app are two views of one session, not two separate ones.

# Test hooks (overridable via env). Defaults match production paths.
SYSTEMD_USER_DIR="${TTYD_SYSTEMD_USER_DIR:-$HOME/.config/systemd/user}"
CONFIG_DIR="${TTYD_CONFIG_DIR:-$HOME/.config/ttyd}"
FORCE_PKG_INSTALLED="${TTYD_FORCE_PKG_INSTALLED:-}"
SKIP_SYSTEMCTL="${TTYD_SKIP_SYSTEMCTL:-}"

PORT="${TTYD_PORT:-7681}"
# Bind to the Tailscale interface by name rather than to an address: the
# address can change, the interface name does not. Binding to 0.0.0.0 would
# expose a full shell to the LAN, so that is never the fallback.
IFACE="${TTYD_INTERFACE:-tailscale0}"
SESSION="${TTYD_TMUX_SESSION:-dotfile}"

SERVICE_FILE="$SYSTEMD_USER_DIR/ttyd.service"
CRED_FILE="$CONFIG_DIR/credentials"

pkg_installed() {
    local pkg="$1"
    if [ -n "$FORCE_PKG_INSTALLED" ]; then
        if [ "$FORCE_PKG_INSTALLED" = "1" ]; then return 0; else return 1; fi
    fi
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
}

run_systemctl() {
    [ -n "$SKIP_SYSTEMCTL" ] && return 0
    systemctl --user "$@"
}

if pkg_installed ttyd && [ -f "$SERVICE_FILE" ] && [ -f "$CRED_FILE" ]; then
    echo "Already installed: ttyd"
    exit 0
fi

if pkg_installed ttyd; then
    echo "Already installed: ttyd (package); configuring service..."
else
    echo "Installing ttyd via apt..."
    sudo apt-get install -y ttyd
fi

# Tailscale is what makes binding to a single interface meaningful. Without it
# the service would come up with nothing to bind to, so say so rather than
# silently falling back to a wider bind.
if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "warning: interface '$IFACE' not found. ttyd will fail to bind until"
    echo "         Tailscale is up. Check with: tailscale status"
fi

mkdir -p "$CONFIG_DIR" "$SYSTEMD_USER_DIR"

if [ -f "$CRED_FILE" ]; then
    echo "Already configured: ttyd credentials"
else
    echo "Generating ttyd password..."
    # A shell on this machine is worth protecting even inside a private
    # tailnet, so generate rather than ship a default anybody could guess.
    # Bound the source first, then filter, then cut. Piping /dev/urandom
    # straight into `head -c` makes head close the pipe, tr take SIGPIPE, and
    # the whole script die under `set -o pipefail` -- the same trap that made
    # nerd_font.sh reinstall on every run. cut reads to EOF, so nothing is
    # killed mid-stream.
    password="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-24)"
    printf '%s:%s\n' "$USER" "$password" > "$CRED_FILE"
    chmod 600 "$CRED_FILE"
fi

echo "Installing ttyd user service..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=ttyd web terminal (tmux session '$SESSION', bound to $IFACE)
After=network-online.target

[Service]
# -W makes the terminal writable: ttyd is read-only by default since 1.7.
# The credential is read from a 0600 file rather than written into the unit,
# though it does still end up in this process's argv and is therefore visible
# to other local users via 'ps'. Acceptable on a single-user desktop; not a
# substitute for the tailscale0 bind, which is what actually limits reach.
ExecStart=/bin/sh -c 'exec /usr/bin/ttyd -W -i $IFACE -p $PORT -c "\$(cat $CRED_FILE)" tmux new -A -s $SESSION'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

run_systemctl daemon-reload
run_systemctl enable --now ttyd.service

# User services stop when the last session ends unless lingering is enabled,
# which would make the terminal unreachable exactly when connecting remotely.
if [ -z "$SKIP_SYSTEMCTL" ] && ! loginctl show-user "$USER" -p Linger 2>/dev/null | grep -q 'Linger=yes'; then
    echo "Enabling lingering so the service survives logout..."
    sudo loginctl enable-linger "$USER" || \
        echo "warning: could not enable lingering; ttyd will stop when you log out."
fi

cat <<EOF

Done. Open this on any device in your tailnet:

  http://\$(tailscale ip -4 2>/dev/null | head -1):$PORT

Username and password are in $CRED_FILE (mode 600):

  $(cat "$CRED_FILE" 2>/dev/null || echo '<unreadable>')

It attaches to tmux session '$SESSION' — the same one an SSH client gets, so
both views share a session rather than opening a second one.

Manage it with:
  systemctl --user status ttyd
  systemctl --user restart ttyd
  systemctl --user disable --now ttyd     # turn it off

Full reference: docs/guides/ttyd.md
EOF
