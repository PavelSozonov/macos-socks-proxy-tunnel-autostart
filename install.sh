#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load config (optional — defaults will be used if .env is missing)
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

# Defaults
SOCKS_PORT="${SOCKS_PORT:-8090}"
SSH_KEY_FILE="${SSH_KEY_FILE:-~/.ssh/id_ed25519}"
SSH_KEY_FILE="${SSH_KEY_FILE/#\~/$HOME}"

SCRIPTS_DIR="$HOME/scripts"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
DOMAIN_TARGET="gui/$(id -u)"

mkdir -p "$SCRIPTS_DIR" "$LAUNCH_AGENTS"

# --- SOCKS Tunnel ---
if [ -z "$SSH_USER" ] || [ -z "$SSH_SERVER" ]; then
    echo "⚠️  SSH_USER/SSH_SERVER not set — skipping SOCKS tunnel (set them in .env)"
else
echo "📦 Installing SOCKS proxy tunnel..."

cat > "$SCRIPTS_DIR/tunnel-proxy.sh" << 'SCRIPT_EOF'
#!/bin/sh
# Resilient SSH tunnel with auto-recovery
# - Exits on any connection failure (launchctl will restart)
# - Fast detection of dead connections via keepalive
# - Connection timeout prevents hanging

exec ssh -D SOCKS_PORT_PLACEHOLDER -q -C -N \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=2 \
    -o ExitOnForwardFailure=yes \
    -o TCPKeepAlive=yes \
    -o ConnectTimeout=10 \
    -o ConnectionAttempts=1 \
    -o BatchMode=yes \
    -i "SSH_KEY_PLACEHOLDER" \
    SSH_USER_PLACEHOLDER@SSH_SERVER_PLACEHOLDER
SCRIPT_EOF

# Replace placeholders with actual values
sed -i '' "s|SOCKS_PORT_PLACEHOLDER|$SOCKS_PORT|g" "$SCRIPTS_DIR/tunnel-proxy.sh"
sed -i '' "s|SSH_KEY_PLACEHOLDER|$SSH_KEY_FILE|g" "$SCRIPTS_DIR/tunnel-proxy.sh"
sed -i '' "s|SSH_USER_PLACEHOLDER|$SSH_USER|g" "$SCRIPTS_DIR/tunnel-proxy.sh"
sed -i '' "s|SSH_SERVER_PLACEHOLDER|$SSH_SERVER|g" "$SCRIPTS_DIR/tunnel-proxy.sh"
chmod +x "$SCRIPTS_DIR/tunnel-proxy.sh"

cat > "$LAUNCH_AGENTS/tunnel-proxy.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>tunnel-proxy</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPTS_DIR/tunnel-proxy.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>NetworkState</key>
        <true/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>$SCRIPTS_DIR/tunnel-proxy.log</string>
    <key>StandardErrorPath</key>
    <string>$SCRIPTS_DIR/tunnel-proxy.log</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF

# Load/reload the service
if launchctl print "$DOMAIN_TARGET/tunnel-proxy" &>/dev/null; then
    launchctl bootout "$DOMAIN_TARGET/tunnel-proxy" 2>/dev/null || true
    sleep 1
fi
launchctl bootstrap "$DOMAIN_TARGET" "$LAUNCH_AGENTS/tunnel-proxy.plist"

echo "✅ SOCKS proxy installed: socks5://127.0.0.1:$SOCKS_PORT"
fi

echo ""
echo "🎉 Done! Your proxy tunnel will auto-start on boot."
echo ""
echo "Useful commands:"
echo "  Check status:  launchctl print gui/\$(id -u)/tunnel-proxy"
echo "  View logs:     tail -f ~/scripts/tunnel-proxy.log"
echo "  Stop:          launchctl kill TERM gui/\$(id -u)/tunnel-proxy"
echo "  Restart:       launchctl kickstart -k gui/\$(id -u)/tunnel-proxy"
echo ""
echo "For gost HTTP proxy, run: ./install-gost.sh"
