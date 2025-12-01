# macOS SSH SOCKS Proxy Auto-Start

Auto-starting SSH tunnel with SOCKS proxy on macOS via launchctl.

Tested on macOS Sequoia 15+ / darwin 25+ (Apple Silicon).

## Quick Setup

```bash
# 1. Clone the repo
git clone https://github.com/your/repo.git && cd repo

# 2. Create .env with your settings
cp .env.template .env
nano .env  # set SSH_USER, SSH_SERVER, SSH_KEY_FILE

# 3. Run installation
./install.sh
```

## Requirements

- SSH key configured for passwordless connection to server
- Default SSH key path: `~/.ssh/id_ed25519`

## Configuration (.env)

| Variable | Description | Example |
|----------|-------------|---------|
| `SSH_USER` | SSH username | `root` |
| `SSH_SERVER` | Server address | `my-server.com` |
| `SSH_KEY_FILE` | Path to SSH private key | `~/.ssh/id_ed25519` |
| `SOCKS_PORT` | SOCKS proxy port | `8090` |
| `HTTP_PORT` | HTTP proxy port (optional) | `8091` |

## Usage

After installation, the proxy automatically starts on system boot.

**SOCKS proxy:** `socks5://127.0.0.1:8090`

**HTTP proxy** (if enabled): `http://127.0.0.1:8091`

### Useful Commands

```bash
# Status
launchctl print gui/$(id -u)/tunnel-proxy

# Logs
tail -f ~/scripts/tunnel-proxy.log

# Restart
launchctl kickstart -k gui/$(id -u)/tunnel-proxy

# Stop
launchctl kill TERM gui/$(id -u)/tunnel-proxy
```

## Uninstall

```bash
./uninstall.sh
```

## Browser Setup

Recommended: **SwitchyOmega** extension for Chrome/Firefox:

1. Create a profile with settings:
   - Protocol: `SOCKS5`
   - Server: `127.0.0.1`
   - Port: `8090`

2. In auto-switch, add rules for desired domains

## HTTP Proxy (Optional)

Useful for apps without SOCKS support (e.g., Docker Desktop free version).

Just set `HTTP_PORT=8091` in `.env` before installation.

## Resilience & Auto-Recovery

The tunnel is configured for maximum reliability:

**SSH options:**
- `ServerAliveInterval=30` — send keepalive every 30 seconds
- `ServerAliveCountMax=2` — disconnect after 2 failed keepalives (~1 min max to detect dead connection)
- `TCPKeepAlive=yes` — enable TCP-level keepalive
- `ConnectTimeout=10` — fail fast if server unreachable
- `ExitOnForwardFailure=yes` — exit if port binding fails

**launchctl options:**
- `KeepAlive.SuccessfulExit=false` — restart on any exit (crash or connection loss)
- `KeepAlive.NetworkState=true` — restart when network becomes available
- `ThrottleInterval=5` — wait 5 seconds between restart attempts
