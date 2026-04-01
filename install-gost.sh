#!/bin/bash
set -e

# Standalone installer for gost HTTP-to-SOCKS proxy bridge
# Pre-requisite: brew install gost

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load config (optional — defaults will be used if .env is missing)
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

# Defaults
SOCKS_PORT="${SOCKS_PORT:-8090}"
GOST_HTTP_PORT="${GOST_HTTP_PORT:-8118}"

SCRIPTS_DIR="$HOME/scripts"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
DOMAIN_TARGET="gui/$(id -u)"

mkdir -p "$SCRIPTS_DIR" "$LAUNCH_AGENTS"

echo "📦 Installing HTTP proxy (gost)..."

# Find gost in common locations
find_gost() {
    command -v gost 2>/dev/null && return
    for p in \
        "/opt/homebrew/bin/gost" \
        "/usr/local/bin/gost"; do
        [ -x "$p" ] && echo "$p" && return
    done
}

GOST_PATH=$(find_gost)

if [ -z "$GOST_PATH" ] || [ ! -x "$GOST_PATH" ]; then
    echo "❌ gost not found. Install it first: brew install gost"
    exit 1
fi

cat > "$SCRIPTS_DIR/gost-proxy.sh" << EOF
#!/bin/sh
exec $GOST_PATH -L http://127.0.0.1:$GOST_HTTP_PORT -F socks5://127.0.0.1:$SOCKS_PORT
EOF
chmod +x "$SCRIPTS_DIR/gost-proxy.sh"

cat > "$LAUNCH_AGENTS/gost-proxy.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>gost-proxy</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPTS_DIR/gost-proxy.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
        <key>NetworkState</key>
        <true/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>$SCRIPTS_DIR/gost-proxy.log</string>
    <key>StandardErrorPath</key>
    <string>$SCRIPTS_DIR/gost-proxy.log</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF

# Load/reload the service
if launchctl print "$DOMAIN_TARGET/gost-proxy" &>/dev/null; then
    launchctl bootout "$DOMAIN_TARGET/gost-proxy" 2>/dev/null || true
    sleep 1
fi
launchctl bootstrap "$DOMAIN_TARGET" "$LAUNCH_AGENTS/gost-proxy.plist"

echo "✅ HTTP proxy (gost) installed: http://127.0.0.1:$GOST_HTTP_PORT → socks5://127.0.0.1:$SOCKS_PORT"
echo ""
echo "Useful commands:"
echo "  Status:   launchctl print gui/\$(id -u)/gost-proxy"
echo "  Logs:     tail -f ~/scripts/gost-proxy.log"
echo "  Stop:     launchctl kill TERM gui/\$(id -u)/gost-proxy"
echo "  Restart:  launchctl kickstart -k gui/\$(id -u)/gost-proxy"
