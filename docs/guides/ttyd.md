# Web Terminal — `ttyd` over Tailscale

A terminal served over HTTP, reachable from a browser on any device in your
tailnet. It attaches to the **same tmux session** an SSH client gets, so the
browser and Termius are two views of one session, not two separate ones.

---

## Why this exists

Input, not convenience.

Android terminal apps — Termius and Termux alike — declare their input field as
"raw, no suggestions". Both Gboard and Samsung Keyboard respond by switching off
the **composing region**, which is exactly what Vietnamese Telex depends on. So
`tieengs` arrives literally instead of `tiếng`.

Nothing on this machine can fix that: the composing is supposed to happen on the
phone, before a byte is ever sent. Established by elimination:

| Where | Composes? |
|---|---|
| Browser text field, same keyboard | ✅ |
| Termius — bare shell prompt | ❌ |
| Termius — inside tmux / a TUI | ❌ |
| Termux | ❌ |

Two independent apps failing with a keyboard that works fine in a browser rules
out both the apps and tmux, and points at how keyboards treat terminal-class
input fields. A browser-based terminal routes input back through the path that
demonstrably still works.

See also: `<Space>tv` in [the nvim guide](nvim.md) solves the same problem for
nvim buffers, server-side, without a browser.

---

## Install

```bash
bash scripts/programs/ttyd.sh
```

Idempotent — re-running prints `Already installed: ttyd` and changes nothing. It
installs the `ttyd` package, generates a password, writes a systemd **user**
service, and enables lingering so the service survives logout.

Then open, from any device in the tailnet:

```
http://<tailscale-ip>:7681
```

Get the address with `tailscale ip -4`. Credentials are in
`~/.config/ttyd/credentials`, mode `600`.

---

## How it is wired

```
ttyd -W -i tailscale0 -p 7681 -c "$(cat ~/.config/ttyd/credentials)" \
     tmux new -A -s dotfile
```

| Flag | Why |
|---|---|
| `-W` | Makes the terminal **writable**. ttyd is read-only by default since 1.7 — without this the browser silently cannot type, which defeats the whole point. |
| `-i tailscale0` | Binds to the Tailscale interface **by name**. The address can change; the interface name does not. |
| `-p 7681` | Port. Override with `TTYD_PORT`. |
| `-c user:pass` | Basic auth, as a second layer behind the tailnet. |
| `tmux new -A -s dotfile` | Attach to the session if it exists, create it otherwise — so you land in the session you already had. |

---

## Security

**ttyd hands a full shell to anyone who can reach it.** Treat the bind address as
the real control:

- **Bound to `tailscale0`, never `0.0.0.0`.** Only devices authenticated into
  your tailnet can reach the port. Binding to all addresses would expose a shell
  to every machine on the LAN. The test suite asserts `0.0.0.0` never appears.
- **The password is defence in depth**, not the primary control. It is generated
  from `/dev/urandom` (24 alphanumeric characters) and stored `600`.
- **Known limitation:** the credential is passed as a command-line argument, so
  it is visible to other local users through `ps`. Acceptable on a single-user
  desktop; not acceptable on a shared machine. If this machine ever gains other
  users, switch to a UNIX socket behind a reverse proxy instead.
- The service runs as **your user**, not root. It is no more privileged than an
  SSH login as yourself — which is exactly as dangerous as that sounds if the
  port is ever exposed.

---

## Managing it

```bash
systemctl --user status ttyd
systemctl --user restart ttyd
systemctl --user disable --now ttyd     # turn it off entirely
journalctl --user -u ttyd -f            # logs
```

---

## Overrides

All read at install time by `scripts/programs/ttyd.sh`:

| Variable | Default | Effect |
|---|---|---|
| `TTYD_PORT` | `7681` | Listening port |
| `TTYD_INTERFACE` | `tailscale0` | Interface to bind |
| `TTYD_TMUX_SESSION` | `dotfile` | Session to attach |
| `TTYD_CONFIG_DIR` | `~/.config/ttyd` | Where credentials live |
| `TTYD_SYSTEMD_USER_DIR` | `~/.config/systemd/user` | Where the unit is written |

`TTYD_FORCE_PKG_INSTALLED` and `TTYD_SKIP_SYSTEMCTL` exist for the test suite,
which exercises the script without root, apt, or systemd.

---

## Troubleshooting

| Symptom | First thing to try |
|---|---|
| Page does not load | `systemctl --user status ttyd`. If it is failing to bind, check `ip link show tailscale0` and `tailscale status`. |
| Service dies after you log out | Lingering is off. `sudo loginctl enable-linger $USER`. |
| Terminal shows output but you cannot type | `-W` is missing from the unit. Re-run `scripts/programs/ttyd.sh`. |
| Browser asks for a password you do not have | `cat ~/.config/ttyd/credentials` |
| Reachable from the LAN, not just the tailnet | The bind is wrong. It must be `-i tailscale0`, never `-p` alone on all addresses. |
