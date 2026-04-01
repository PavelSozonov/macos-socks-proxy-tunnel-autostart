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
```

## Uninstall

```bash
./uninstall.sh       # removes SOCKS tunnel
./uninstall-gost.sh  # removes gost HTTP proxy
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
