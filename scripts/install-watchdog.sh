#!/bin/bash
set -e

# Standalone installer for the tunnel watchdog.
# Performs an end-to-end health check through the SOCKS proxy on a schedule
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
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-30}"
WATCHDOG_URL="${WATCHDOG_URL:-https://www.google.com/generate_204}"
WATCHDOG_FAILURES="${WATCHDOG_FAILURES:-2}"
WATCHDOG_TIMEOUT="${WATCHDOG_TIMEOUT:-10}"

SCRIPTS_DIR="$HOME/scripts"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
DOMAIN_TARGET="gui/$(id -u)"

mkdir -p "$SCRIPTS_DIR" "$LAUNCH_AGENTS"

echo "📦 Installing tunnel watchdog..."

cat > "$SCRIPTS_DIR/tunnel-watchdog.sh" << 'SCRIPT_EOF'
#!/bin/sh
# Tunnel watchdog: end-to-end health check through the SOCKS proxy.
# Restarts tunnel-proxy after N consecutive failures.
# gost (if used) is stateless and reconnects to the new tunnel on its own.

SOCKS_PORT="SOCKS_PORT_PLACEHOLDER"
URL="WATCHDOG_URL_PLACEHOLDER"
MAX_FAILURES="WATCHDOG_FAILURES_PLACEHOLDER"
TIMEOUT="WATCHDOG_TIMEOUT_PLACEHOLDER"

DOMAIN_TARGET="gui/$(id -u)"
STATE_FILE="$HOME/scripts/tunnel-watchdog.state"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

# Nothing to watch if the tunnel service is not loaded
launchctl print "$DOMAIN_TARGET/tunnel-proxy" >/dev/null 2>&1 || exit 0

if curl --socks5-hostname "127.0.0.1:$SOCKS_PORT" -m "$TIMEOUT" -fsS -o /dev/null "$URL"; then
    rm -f "$STATE_FILE"
    exit 0
fi

failures=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
failures=$((failures + 1))
echo "$failures" > "$STATE_FILE"
log "health check failed ($failures/$MAX_FAILURES)"

[ "$failures" -ge "$MAX_FAILURES" ] || exit 0

log "restarting tunnel-proxy"
launchctl kickstart -k "$DOMAIN_TARGET/tunnel-proxy"
rm -f "$STATE_FILE"
SCRIPT_EOF

sed -i '' "s|SOCKS_PORT_PLACEHOLDER|$SOCKS_PORT|g" "$SCRIPTS_DIR/tunnel-watchdog.sh"
sed -i '' "s|WATCHDOG_URL_PLACEHOLDER|$WATCHDOG_URL|g" "$SCRIPTS_DIR/tunnel-watchdog.sh"
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
    <key>StartInterval</key>
    <integer>$WATCHDOG_INTERVAL</integer>
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

echo "✅ Watchdog installed: checks $WATCHDOG_URL via socks5://127.0.0.1:$SOCKS_PORT every ${WATCHDOG_INTERVAL}s, restarts after $WATCHDOG_FAILURES failures"
echo ""
echo "Useful commands:"
echo "  Status:   launchctl print gui/\$(id -u)/tunnel-watchdog"
echo "  Logs:     tail -f ~/scripts/tunnel-watchdog.log"
echo "  Run now:  launchctl kickstart gui/\$(id -u)/tunnel-watchdog"
