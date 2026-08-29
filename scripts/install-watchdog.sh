#!/bin/bash
set -e

# Standalone installer for the tunnel watchdog.
# Runs an end-to-end health check through the SOCKS proxy in a loop
# and restarts the tunnel when the check keeps failing.
# This catches "half-dead" SSH sessions (e.g. after VPN on/off) that launchd
# cannot detect because the ssh process is still alive.

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Load config (optional — defaults will be used if .env is missing)
if [ -f "$REPO_DIR/.env" ]; then
    source "$REPO_DIR/.env"
fi

# Defaults
SOCKS_PORT="${SOCKS_PORT:-8090}"
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-3}"
WATCHDOG_INTERVAL_BATTERY="${WATCHDOG_INTERVAL_BATTERY:-60}"
WATCHDOG_URL="${WATCHDOG_URL:-https://www.google.com/generate_204}"
WATCHDOG_FAILURES="${WATCHDOG_FAILURES:-2}"
WATCHDOG_TIMEOUT="${WATCHDOG_TIMEOUT:-3}"

SCRIPTS_DIR="$HOME/scripts"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
DOMAIN_TARGET="gui/$(id -u)"

mkdir -p "$SCRIPTS_DIR" "$LAUNCH_AGENTS"

echo "📦 Installing tunnel watchdog..."

cat > "$SCRIPTS_DIR/tunnel-watchdog.sh" << 'SCRIPT_EOF'
#!/bin/sh
# Tunnel watchdog: end-to-end health check through the SOCKS proxy.
# Runs as a loop under launchd KeepAlive (launchd's own StartInterval timers are
# coalesced to ~10s granularity, too coarse for fast recovery).
# Restarts tunnel-proxy after N consecutive failures.
# gost (if used) is stateless and reconnects to the new tunnel on its own.

SOCKS_PORT="SOCKS_PORT_PLACEHOLDER"
URL="WATCHDOG_URL_PLACEHOLDER"
INTERVAL_AC="WATCHDOG_INTERVAL_PLACEHOLDER"
INTERVAL_BATTERY="WATCHDOG_INTERVAL_BATTERY_PLACEHOLDER"
MAX_FAILURES="WATCHDOG_FAILURES_PLACEHOLDER"
TIMEOUT="WATCHDOG_TIMEOUT_PLACEHOLDER"

DOMAIN_TARGET="gui/$(id -u)"
# Grace period after a restart for the new ssh to connect (matches ConnectTimeout)
GRACE=10

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

# Check less often on battery to let the radio/SoC idle
interval() {
    case "$(pmset -g batt 2>/dev/null | head -1)" in
        *Battery*) echo "$INTERVAL_BATTERY" ;;
        *)         echo "$INTERVAL_AC" ;;
    esac
}

failures=0
while true; do
    # Nothing to watch if the tunnel service is not loaded
    if ! launchctl print "$DOMAIN_TARGET/tunnel-proxy" >/dev/null 2>&1; then
        failures=0
        sleep "$(interval)"
        continue
    fi

    if curl --socks5-hostname "127.0.0.1:$SOCKS_PORT" -m "$TIMEOUT" -fsS -o /dev/null "$URL"; then
        failures=0
        sleep "$(interval)"
        continue
    fi

    failures=$((failures + 1))
    log "health check failed ($failures/$MAX_FAILURES)"

    if [ "$failures" -ge "$MAX_FAILURES" ]; then
        log "restarting tunnel-proxy"
        launchctl kickstart -k "$DOMAIN_TARGET/tunnel-proxy"
        failures=0
        sleep "$GRACE"
    else
        sleep "$(interval)"
    fi
done
SCRIPT_EOF

sed -i '' "s|SOCKS_PORT_PLACEHOLDER|$SOCKS_PORT|g" "$SCRIPTS_DIR/tunnel-watchdog.sh"
sed -i '' "s|WATCHDOG_URL_PLACEHOLDER|$WATCHDOG_URL|g" "$SCRIPTS_DIR/tunnel-watchdog.sh"
sed -i '' "s|WATCHDOG_INTERVAL_BATTERY_PLACEHOLDER|$WATCHDOG_INTERVAL_BATTERY|g" "$SCRIPTS_DIR/tunnel-watchdog.sh"
sed -i '' "s|WATCHDOG_INTERVAL_PLACEHOLDER|$WATCHDOG_INTERVAL|g" "$SCRIPTS_DIR/tunnel-watchdog.sh"
sed -i '' "s|WATCHDOG_FAILURES_PLACEHOLDER|$WATCHDOG_FAILURES|g" "$SCRIPTS_DIR/tunnel-watchdog.sh"
sed -i '' "s|WATCHDOG_TIMEOUT_PLACEHOLDER|$WATCHDOG_TIMEOUT|g" "$SCRIPTS_DIR/tunnel-watchdog.sh"
chmod +x "$SCRIPTS_DIR/tunnel-watchdog.sh"

cat > "$LAUNCH_AGENTS/tunnel-watchdog.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>tunnel-watchdog</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPTS_DIR/tunnel-watchdog.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>$SCRIPTS_DIR/tunnel-watchdog.log</string>
    <key>StandardErrorPath</key>
    <string>$SCRIPTS_DIR/tunnel-watchdog.log</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF

# Load/reload the service
if launchctl print "$DOMAIN_TARGET/tunnel-watchdog" &>/dev/null; then
    launchctl bootout "$DOMAIN_TARGET/tunnel-watchdog" 2>/dev/null || true
    sleep 1
fi
launchctl bootstrap "$DOMAIN_TARGET" "$LAUNCH_AGENTS/tunnel-watchdog.plist"

echo "✅ Watchdog installed: checks $WATCHDOG_URL via socks5://127.0.0.1:$SOCKS_PORT every ${WATCHDOG_INTERVAL}s (${WATCHDOG_INTERVAL_BATTERY}s on battery), restarts after $WATCHDOG_FAILURES failures"
echo ""
echo "Useful commands:"
echo "  Status:   launchctl print gui/\$(id -u)/tunnel-watchdog"
echo "  Logs:     tail -f ~/scripts/tunnel-watchdog.log"
echo "  Restart:  launchctl kickstart -k gui/\$(id -u)/tunnel-watchdog"
