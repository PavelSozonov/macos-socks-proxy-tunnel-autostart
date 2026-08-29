# macOS SSH SOCKS Proxy Auto-Start

Set up an SSH SOCKS proxy on your Mac **once** and never touch it again.

`ssh -D` is easy; keeping it alive is not. The tunnel dies on reboot, sleep, Wi-Fi changes and VPN toggles — and often stays *half-dead*: the `ssh` process is still running but no traffic goes through, so nothing restarts it. This repo turns `ssh -D` into a self-healing background service:

- **Starts on login, restarts on failure** — managed by launchd, no terminal window to keep open
- **Detects half-dead tunnels** — a watchdog sends real traffic through the proxy and restarts the tunnel when it stops passing (recovery in ~15s; slower on battery to save power)
- **Works with apps that only speak HTTP** — optional [gost](https://github.com/go-gost/gost) bridge exposes the same tunnel as an HTTP proxy (e.g. for Docker Desktop)
- **No personal data in the repo** — server, user, key and ports live in a git-ignored `.env`

```
app ── socks5://127.0.0.1:8090 ──▶ ssh -D ──▶ your server ──▶ internet
app ── http://127.0.0.1:8118 ──▶ gost ──┘
watchdog ── curl through socks5 every 3s ──▶ no response twice? restart ssh -D
```

Requires only macOS built-ins (`ssh`, `launchd`, `curl`) plus an SSH key that logs into your server without a password. Tested on macOS Sequoia 15+ (Apple Silicon).

## Quick Setup

```bash
# 0. On the server: create a forward-only SSH user (recommended, see docs/server-setup.md)

# 1. Create .env with your settings
cp .env.template .env
vim .env  # set SSH_USER, SSH_SERVER, SSH_KEY_FILE

# 2. Install everything: SOCKS tunnel + gost HTTP bridge + watchdog
make install
```

Or pick the parts you need:

```bash
make install-tunnel     # SSH SOCKS tunnel
make install-gost       # HTTP-to-SOCKS bridge (requires: brew install gost)
make install-watchdog   # auto-heals a stuck tunnel (e.g. after VPN on/off)
make help               # all targets
```

The underlying scripts live in `scripts/` and can also be run directly.

`.env` is optional — all scripts use sensible defaults (`SOCKS_PORT=8090`, `GOST_HTTP_PORT=8118`). The SOCKS tunnel requires `SSH_USER` and `SSH_SERVER` to be set; gost works out of the box.

## Requirements

- SSH key configured for passwordless connection to server — ideally a dedicated account that can only forward ports, see [docs/server-setup.md](docs/server-setup.md)
- Default SSH key path: `~/.ssh/id_ed25519`
- For HTTP proxy: `brew install gost`

## Configuration (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| `SSH_USER` | SSH username | *(required for tunnel)* |
| `SSH_SERVER` | Server address | *(required for tunnel)* |
| `SSH_KEY_FILE` | Path to SSH private key | `~/.ssh/id_ed25519` |
| `SOCKS_PORT` | SOCKS proxy port | `8090` |
| `GOST_HTTP_PORT` | HTTP proxy port (gost) | `8118` |
| `WATCHDOG_INTERVAL` | Seconds between watchdog health checks | `5` |
| `WATCHDOG_URL` | URL fetched through the SOCKS proxy as a health check | `https://www.google.com/generate_204` |
| `WATCHDOG_FAILURES` | Consecutive failures before restarting the tunnel | `2` |
| `WATCHDOG_TIMEOUT` | Health check timeout in seconds | `4` |

## Usage

After installation, services automatically start on system boot.

**SOCKS proxy:** `socks5://127.0.0.1:8090`

**HTTP proxy** (if gost installed): `http://127.0.0.1:8118`

### Useful Commands

```bash
make status    # state of all services
make logs      # tail all logs
make restart   # restart the SSH tunnel now
make check     # run the health check through the SOCKS proxy once
```

Under the hood (per service):

```bash
# --- SOCKS tunnel ---
launchctl print gui/$(id -u)/tunnel-proxy     # status
tail -f ~/scripts/tunnel-proxy.log             # logs
launchctl kickstart -k gui/$(id -u)/tunnel-proxy  # restart
launchctl kill TERM gui/$(id -u)/tunnel-proxy     # stop

# --- gost HTTP proxy ---
launchctl print gui/$(id -u)/gost-proxy       # status
tail -f ~/scripts/gost-proxy.log              # logs
launchctl kickstart -k gui/$(id -u)/gost-proxy   # restart
launchctl kill TERM gui/$(id -u)/gost-proxy      # stop

# --- watchdog ---
launchctl print gui/$(id -u)/tunnel-watchdog   # status
tail -f ~/scripts/tunnel-watchdog.log          # logs (restarts only)
launchctl kickstart -k gui/$(id -u)/tunnel-watchdog  # restart
```

## Uninstall

```bash
make uninstall            # removes everything
make uninstall-tunnel     # or individually
make uninstall-gost
make uninstall-watchdog
```

## HTTP Proxy (gost)

[gost](https://github.com/go-gost/gost) bridges HTTP to SOCKS for apps that don't support SOCKS natively (e.g., Docker Desktop free version).

It runs as a separate launchd service and can be installed/uninstalled independently from the SOCKS tunnel:

```bash
brew install gost      # pre-requisite
make install-gost      # install & start
make uninstall-gost    # remove
```

The proxy chain: `http://127.0.0.1:8118` -> `socks5://127.0.0.1:8090` -> SSH tunnel -> internet.

## Watchdog

launchd only restarts the tunnel when the `ssh` process **exits**. After toggling a VPN (or otherwise changing routes) the process often stays alive while the connection is half-dead, so SOCKS traffic silently stops and launchd sees nothing wrong.

The watchdog is a separate launchd agent (a loop under `KeepAlive`) that every `WATCHDOG_INTERVAL` seconds (`WATCHDOG_INTERVAL_BATTERY` on battery, to let the radio idle) performs a real end-to-end check:

```
curl --socks5-hostname 127.0.0.1:$SOCKS_PORT -m $WATCHDOG_TIMEOUT -fsS $WATCHDOG_URL
```

After `WATCHDOG_FAILURES` consecutive failures it runs `launchctl kickstart -k` on `tunnel-proxy`. With the defaults a half-dead tunnel is back within **~15 seconds** worst case (≤3s until the next check, two checks of ≤3s each, 3s between them, ssh reconnect); after a restart the watchdog pauses for 10s so the reconnecting tunnel is not restarted again. On battery the same sequence takes up to ~2 minutes. gost does not need a restart: it is stateless and opens a fresh connection to the SOCKS port per request, so it picks up the new tunnel automatically. Successful checks are not logged; failures and restarts go to `~/scripts/tunnel-watchdog.log`. If `tunnel-proxy` is not loaded, the watchdog does nothing.

```bash
make install-watchdog    # install & start
make uninstall-watchdog  # remove
```

## Browser Setup

Recommended: **SwitchyOmega** extension for Chrome/Firefox:

1. Create a profile with settings:
   - Protocol: `SOCKS5`
   - Server: `127.0.0.1`
   - Port: `8090`

2. In auto-switch, add rules for desired domains

## Resilience & Auto-Recovery

Both services are configured for maximum reliability via launchd.

**SSH options:**
- `ServerAliveInterval=30` — send keepalive every 30 seconds
- `ServerAliveCountMax=2` — disconnect after 2 failed keepalives (~1 min max to detect dead connection)
- `TCPKeepAlive=yes` — enable TCP-level keepalive
- `ConnectTimeout=10` — fail fast if server unreachable
- `ExitOnForwardFailure=yes` — exit if port binding fails

**launchctl options (both tunnel and gost):**
- `KeepAlive.NetworkState=true` — always restart when network is available (regardless of exit code)
- `ThrottleInterval=5` — wait 5 seconds between restart attempts

**Watchdog (optional, see above):** end-to-end check through the proxy that restarts a tunnel whose process is alive but no longer passes traffic.
