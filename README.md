# macOS SSH SOCKS Proxy Auto-Start

Set up an SSH SOCKS proxy on your Mac **once** and never touch it again.

`ssh -D` is easy; keeping it alive is not. The tunnel dies on reboot, sleep, Wi-Fi changes and VPN toggles — and often stays *half-dead*: the `ssh` process is still running but no traffic goes through, so nothing restarts it. This repo turns `ssh -D` into a self-healing background service:

- **Starts on login, restarts on failure** — managed by launchd, no terminal window to keep open
- **Detects half-dead tunnels** — a watchdog sends real traffic through the proxy and restarts the tunnel when it stops passing (recovery in ~35s; slower on battery to save power)
- **Works with apps that only speak HTTP** — a [gost](https://github.com/go-gost/gost) bridge exposes the same tunnel as an HTTP proxy (e.g. for Docker Desktop)
- **No personal data in the repo** — server, user, key and ports live in a git-ignored `.env`

```
app ── socks5://127.0.0.1:8090 ──▶ ssh -D ──▶ your server ──▶ internet
app ── http://127.0.0.1:8118 ──▶ gost ──┘
watchdog ── curl through socks5 every 3s ──▶ no response 3 times in a row? restart ssh -D
```

Requires macOS built-ins (`ssh`, `launchd`, `curl`), an SSH key that logs into your server without a password, and one Homebrew package: `brew install gost` for the HTTP bridge. Tested on macOS Sequoia 15+ (Apple Silicon).

## Quick Setup

**0.** On the server, create a forward-only SSH user — recommended, see
[docs/server-setup.md](docs/server-setup.md).

**1.** Create `.env` and set `SSH_USER`, `SSH_SERVER` and `SSH_KEY_FILE` in it:

```bash
cp .env.template .env
vim .env
```

**2.** Install gost, then everything else — SOCKS tunnel, gost HTTP bridge, watchdog and log cap:

```bash
brew install gost
make install
```

`make install` checks for gost before touching anything and stops with a reminder to run `brew install gost` if it is missing, so a forgotten step never leaves a half-installed setup.

Or pick the parts you need:

| Command | Installs |
|---------|----------|
| `make install-tunnel` | SSH SOCKS tunnel |
| `make install-gost` | HTTP-to-SOCKS bridge (needs `brew install gost` first) |
| `make install-watchdog` | auto-healing for a stuck tunnel (e.g. after VPN on/off) |
| `make install-log-cap` | keeps the service logs from growing without bound |
| `make help` | *(lists all targets)* |

The underlying scripts live in `scripts/` and can also be run directly.

`.env` is optional — all scripts use sensible defaults (`SOCKS_PORT=8090`, `GOST_HTTP_PORT=8118`). The SOCKS tunnel requires `SSH_USER` and `SSH_SERVER` to be set; gost works out of the box.

## Requirements

- SSH key configured for passwordless connection to server — ideally a dedicated account that can only forward ports, see [docs/server-setup.md](docs/server-setup.md)
- Default SSH key path: `~/.ssh/id_ed25519`
- `brew install gost` for the HTTP proxy — the only non-built-in dependency. `make install` and `make install-gost` refuse to run without it; `make install-tunnel` and `make install-watchdog` alone do not need it

## Configuration (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| `SSH_USER` | SSH username | *(required for tunnel)* |
| `SSH_SERVER` | Server address | *(required for tunnel)* |
| `SSH_KEY_FILE` | Path to SSH private key | `~/.ssh/id_ed25519` |
| `SOCKS_PORT` | SOCKS proxy port | `8090` |
| `GOST_HTTP_PORT` | HTTP proxy port (gost) | `8118` |
| `WATCHDOG_INTERVAL` | Seconds between watchdog health checks (on AC power) | `3` |
| `WATCHDOG_INTERVAL_BATTERY` | Same, on battery power (saves energy) | `60` |
| `WATCHDOG_URL` | URL fetched through the SOCKS proxy as a health check | `http://www.google.com/generate_204` |
| `WATCHDOG_FAILURES` | Consecutive failures before restarting the tunnel | `3` |
| `WATCHDOG_TIMEOUT` | Health check timeout in seconds | `8` |

## Usage

After installation, services automatically start on system boot.

**SOCKS proxy:** `socks5://127.0.0.1:8090`

**HTTP proxy** (if gost installed): `http://127.0.0.1:8118`

### Useful Commands

| Command | Does |
|---------|------|
| `make status` | state of all services |
| `make logs` | tail all logs |
| `make restart` | restart the SSH tunnel now |
| `make check` | run the health check through the SOCKS proxy once |

Under the hood every part is a launchd agent. Replace `<service>` below with
`tunnel-proxy`, `gost-proxy` or `tunnel-watchdog`:

| Action | Command |
|--------|---------|
| Status | `launchctl print gui/$(id -u)/<service>` |
| Restart | `launchctl kickstart -k gui/$(id -u)/<service>` |
| Stop | `launchctl kill TERM gui/$(id -u)/<service>` |
| Logs | `tail -f ~/scripts/<service>.log` |

## Moving to a New Mac

Migration Assistant carries the services over: `~/scripts`, the launchd agents in
`~/Library/LaunchAgents`, `~/.ssh` and this repo with its `.env` all live in your
home folder, so the SOCKS tunnel and the watchdog come up on the first login of
the new machine. The one thing that does not migrate is `gost` — it is a Homebrew
binary outside your home folder, and `~/scripts/gost-proxy.sh` points at it by
absolute path. Until you reinstall it, port 8118 refuses connections and
`~/scripts/gost-proxy.log` fills with `gost: not found`.

Fix it by installing gost and regenerating the bridge, which also refreshes the
path in case the old Mac was Intel (`/usr/local/bin`) and the new one is Apple
Silicon (`/opt/homebrew/bin`):

```bash
brew install gost
make install-gost
make status
```

Do not put a different proxy on 8118 (Privoxy, for example): it would take the
port gost needs and, with its default config, send traffic straight to the
internet instead of through the tunnel.

## Uninstall

```bash
make uninstall
```

Or individually: `make uninstall-tunnel`, `make uninstall-gost`,
`make uninstall-watchdog`.

## HTTP Proxy (gost)

[gost](https://github.com/go-gost/gost) bridges HTTP to SOCKS for apps that don't support SOCKS natively (e.g., Docker Desktop free version).

It runs as a separate launchd service and can be installed/uninstalled independently from the SOCKS tunnel:

```bash
brew install gost
make install-gost
```

Remove it with `make uninstall-gost`.

The proxy chain: `http://127.0.0.1:8118` -> `socks5://127.0.0.1:8090` -> SSH tunnel -> internet.

## Watchdog

launchd only restarts the tunnel when the `ssh` process **exits**. After toggling a VPN (or otherwise changing routes) the process often stays alive while the connection is half-dead, so SOCKS traffic silently stops and launchd sees nothing wrong.

The watchdog is a separate launchd agent (a loop under `KeepAlive`) that every `WATCHDOG_INTERVAL` seconds (`WATCHDOG_INTERVAL_BATTERY` on battery, to let the radio idle) performs a real end-to-end check:

```
curl --socks5-hostname 127.0.0.1:$SOCKS_PORT -m $WATCHDOG_TIMEOUT -fsS $WATCHDOG_URL
```

After `WATCHDOG_FAILURES` consecutive failures it runs `launchctl kickstart -k` on `tunnel-proxy`. With the defaults a half-dead tunnel is back within **~35 seconds** worst case (≤3s until the next check, three checks of ≤8s each, 3s between them, ssh reconnect); after a restart the watchdog pauses for 10s so the reconnecting tunnel is not restarted again. On battery the same sequence takes up to ~3.5 minutes.

The defaults trade recovery time for fewer false restarts, and that trade was measured. With 2 failures of 3 s, a link whose round-trip time jumped from ~6 ms to 375 ms at the first provider hop, with a few percent loss, made a working tunnel take 1–6 s for the check's TLS handshake, and the watchdog restarted it 10–74 times a day. A restart cannot help there — the new connection takes the same path — so every one of them was an outage of its own. If your link is clean and you want faster recovery, lower `WATCHDOG_TIMEOUT` in `.env`.

The check uses plain HTTP, not HTTPS, for the same reason: TLS adds one more round trip through the tunnel to every check, and on a jittery link every round trip is another chance to miss the timeout. Measured through the same tunnel, the 90th percentile was 0.76 s over HTTP against 1.55 s over HTTPS, while switching the target from Google to Cloudflare changed nothing. Plain HTTP costs no privacy here: the request travels inside ssh up to your server, and the check still exercises the whole path — SOCKS, ssh, server, internet.

gost does not need a restart: it is stateless and opens a fresh connection to the SOCKS port per request, so it picks up the new tunnel automatically. Successful checks are not logged; failures and restarts go to `~/scripts/tunnel-watchdog.log`. If `tunnel-proxy` is not loaded, the watchdog does nothing.

```bash
make install-watchdog
```

Remove it with `make uninstall-watchdog`.

## Log Size Cap

`gost` logs one line per proxied request — around 1.4 KB — and launchd writes it
to a plain file with no rotation, so the bridge log grows without bound. On one
machine it was found at **3.3 GB**, holding a line for every host visited
through the proxy.

```bash
make install-log-cap
```

A launchd agent checks the service logs every `LOG_CAP_INTERVAL` seconds
(default 300) and truncates any that passed `LOG_CAP_BYTES` (default 100 MiB).
Right before truncating it copies the last `LOG_CAP_KEEP_LINES` lines (default
2000) to `<log>.prev`, so a truncation does not leave you with an empty file at
the moment something needs diagnosing.

It truncates **in place** rather than rotating, and that is deliberate: launchd
holds these files open through `StandardOutPath` in append mode, so renaming one
would leave the service writing into the renamed file while the fresh one stayed
empty until the next restart. Truncating keeps the same inode, frees the space
immediately, and append mode makes writes resume at offset 0 instead of leaving
a sparse hole.

The trade-off is that history is discarded rather than archived. For a debug log
of proxied requests that is the point — the alternative is keeping a compressed
record of every host visited.

### The bridge itself logs only failures

`GOST_LOG_LEVEL` (default `warn`) is the other half of the fix, and the more
important one. At gost's default `info` level every proxied request costs four
log lines — one of them carrying the destination host — which measured at 125 MB
a day of ordinary use. The level cannot be lowered with a flag (`-D`/`-DD` only
raise it), so `install-gost.sh` writes `~/scripts/gost-proxy.yml` and runs the
bridge with `-C`; that config is gost's own serialisation of the former flags
plus a `log` section.

At `warn` only failures remain, which measured at 7% of the volume. `warn` rather
than `error` because this binary emits no warn-level events at all — 0 out of
3231 lines sampled — so the tier costs nothing and stays available if a future
version starts using it. Note that the startup `listening on …` line is `info`
too, so it is no longer logged; `launchctl print gui/$(id -u)/gost-proxy` shows
the state instead.

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

## Development

CI runs [pre-commit](https://pre-commit.com) on every push and pull request: trailing whitespace, file endings, merge markers, YAML, shebangs, private keys and `shellcheck` on the scripts. Run the same checks locally with `make lint`, or once per clone install the git hook so they run on every commit:

```bash
brew install pre-commit
pre-commit install
```
