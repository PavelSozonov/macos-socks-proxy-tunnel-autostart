# macOS SSH SOCKS Proxy Auto-Start

Auto-starting SSH tunnel with SOCKS proxy on macOS via launchctl.

Tested on macOS Sequoia 15+ / darwin 25+ (Apple Silicon).

## Quick Setup

```bash
# 1. Create .env with your settings
cp .env.template .env
vim .env  # set SSH_USER, SSH_SERVER, SSH_KEY_FILE

# 2. Install SOCKS tunnel
bash ./install.sh

# 3. (Optional) Install HTTP proxy bridge via gost
bash ./install-gost.sh

# 4. (Recommended) Install watchdog — auto-heals a stuck tunnel (e.g. after VPN on/off)
bash ./install-watchdog.sh
```

`.env` is optional — both scripts use sensible defaults (`SOCKS_PORT=8090`, `GOST_HTTP_PORT=8118`). The SOCKS tunnel requires `SSH_USER` and `SSH_SERVER` to be set; gost works out of the box.

## Requirements

- SSH key configured for passwordless connection to server
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
| `WATCHDOG_INTERVAL` | Seconds between watchdog health checks | `30` |
| `WATCHDOG_URL` | URL fetched through the SOCKS proxy as a health check | `https://www.google.com/generate_204` |
| `WATCHDOG_FAILURES` | Consecutive failures before restarting the tunnel | `2` |
| `WATCHDOG_TIMEOUT` | Health check timeout in seconds | `10` |

## Usage

After installation, services automatically start on system boot.

**SOCKS proxy:** `socks5://127.0.0.1:8090`

**HTTP proxy** (if gost installed): `http://127.0.0.1:8118`

### Useful Commands

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
launchctl kickstart gui/$(id -u)/tunnel-watchdog  # run check now
```

## Uninstall

```bash
./uninstall.sh       # removes SOCKS tunnel
./uninstall-gost.sh  # removes gost HTTP proxy
./uninstall-watchdog.sh  # removes watchdog
```

## HTTP Proxy (gost)

[gost](https://github.com/go-gost/gost) bridges HTTP to SOCKS for apps that don't support SOCKS natively (e.g., Docker Desktop free version).

It runs as a separate launchd service and can be installed/uninstalled independently from the SOCKS tunnel:

```bash
brew install gost        # pre-requisite
bash ./install-gost.sh   # install & start
bash ./uninstall-gost.sh # remove
```

The proxy chain: `http://127.0.0.1:8118` -> `socks5://127.0.0.1:8090` -> SSH tunnel -> internet.

## Watchdog

launchd only restarts the tunnel when the `ssh` process **exits**. After toggling a VPN (or otherwise changing routes) the process often stays alive while the connection is half-dead, so SOCKS traffic silently stops and launchd sees nothing wrong.

The watchdog is a separate launchd agent that runs every `WATCHDOG_INTERVAL` seconds and performs a real end-to-end check:

```
curl --socks5-hostname 127.0.0.1:$SOCKS_PORT -m $WATCHDOG_TIMEOUT -fsS $WATCHDOG_URL
```

After `WATCHDOG_FAILURES` consecutive failures it runs `launchctl kickstart -k` on `tunnel-proxy`. gost does not need a restart: it is stateless and opens a fresh connection to the SOCKS port per request, so it picks up the new tunnel automatically. Successful checks are not logged; failures and restarts go to `~/scripts/tunnel-watchdog.log`. If `tunnel-proxy` is not loaded, the watchdog does nothing.

```bash
bash ./install-watchdog.sh    # install & start
bash ./uninstall-watchdog.sh  # remove
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
