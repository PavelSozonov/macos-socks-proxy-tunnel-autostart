#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load config
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "❌ .env not found. Copy .env.template to .env and fill in your settings:"
    echo "   cp .env.template .env"
    exit 1
fi
source "$SCRIPT_DIR/.env"

# Validate required settings
if [ -z "$SSH_USER" ] || [ -z "$SSH_SERVER" ]; then
    echo "❌ SSH_USER and SSH_SERVER must be set in .env"
    exit 1
fi

# Expand ~ in path
SSH_KEY_FILE="${SSH_KEY_FILE/#\~/$HOME}"
SOCKS_PORT="${SOCKS_PORT:-8090}"

SCRIPTS_DIR="$HOME/scripts"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
DOMAIN_TARGET="gui/$(id -u)"

mkdir -p "$SCRIPTS_DIR" "$LAUNCH_AGENTS"

# --- SOCKS Tunnel ---
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
        <key>SuccessfulExit</key>
        <false/>
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

# --- Optional: HTTP Proxy (pproxy) ---
if [ -n "$HTTP_PORT" ]; then
    echo "📦 Installing HTTP proxy (pproxy)..."
    
    # Find pproxy in common locations
    find_pproxy() {
        command -v pproxy 2>/dev/null && return
        for p in \
            "$HOME/.local/bin/pproxy" \
            "$(python3 -c 'import site; print(site.USER_BASE)' 2>/dev/null)/bin/pproxy" \
            "/opt/homebrew/bin/pproxy" \
            "/usr/local/bin/pproxy"; do
            [ -x "$p" ] && echo "$p" && return
        done
    }
    
    PPROXY_PATH=$(find_pproxy)
    
    if [ -z "$PPROXY_PATH" ]; then
        echo "   Installing pproxy..."
        if command -v pipx &>/dev/null; then
            pipx install pproxy --quiet
        else
            pip3 install --user --quiet --break-system-packages pproxy 2>/dev/null || \
            pip3 install --user --quiet pproxy
        fi
        PPROXY_PATH=$(find_pproxy)
    fi
    
    if [ -z "$PPROXY_PATH" ] || [ ! -x "$PPROXY_PATH" ]; then
        echo "❌ Failed to find pproxy after installation"
        exit 1
    fi

    cat > "$SCRIPTS_DIR/pproxy.sh" << EOF
#!/bin/sh
exec $PPROXY_PATH -r socks://127.0.0.1:$SOCKS_PORT -l http://:$HTTP_PORT
EOF
    chmod +x "$SCRIPTS_DIR/pproxy.sh"

    cat > "$LAUNCH_AGENTS/pproxy.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>pproxy</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPTS_DIR/pproxy.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>$SCRIPTS_DIR/pproxy.log</string>
    <key>StandardErrorPath</key>
    <string>$SCRIPTS_DIR/pproxy.log</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF

    if launchctl print "$DOMAIN_TARGET/pproxy" &>/dev/null; then
        launchctl bootout "$DOMAIN_TARGET/pproxy" 2>/dev/null || true
        sleep 1
    fi
    launchctl bootstrap "$DOMAIN_TARGET" "$LAUNCH_AGENTS/pproxy.plist"
    
    echo "✅ HTTP proxy installed: http://127.0.0.1:$HTTP_PORT"
fi

echo ""
echo "🎉 Done! Your proxy tunnel will auto-start on boot."
echo ""
echo "Useful commands:"
echo "  Check status:  launchctl print gui/\$(id -u)/tunnel-proxy"
echo "  View logs:     tail -f ~/scripts/tunnel-proxy.log"
echo "  Stop:          launchctl kill TERM gui/\$(id -u)/tunnel-proxy"
echo "  Restart:       launchctl kickstart -k gui/\$(id -u)/tunnel-proxy"

