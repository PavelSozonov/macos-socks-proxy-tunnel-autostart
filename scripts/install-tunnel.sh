#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Load config (optional — defaults will be used if .env is missing)
if [ -f "$REPO_DIR/.env" ]; then
    # .env is optional, git-ignored and absent in CI: nothing for shellcheck to follow.
    # shellcheck source=/dev/null
    source "$REPO_DIR/.env"
fi

# Defaults
SOCKS_PORT="${SOCKS_PORT:-8090}"
SSH_KEY_FILE="${SSH_KEY_FILE:-~/.ssh/id_ed25519}"
SSH_KEY_FILE="${SSH_KEY_FILE/#\~/$HOME}"
SSH_JUMP="${SSH_JUMP:-}"
SSH_JUMP_HOST_KEY_SHA256="${SSH_JUMP_HOST_KEY_SHA256:-}"

SCRIPTS_DIR="$HOME/scripts"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
DOMAIN_TARGET="gui/$(id -u)"

mkdir -p "$SCRIPTS_DIR" "$LAUNCH_AGENTS"

# --- SOCKS Tunnel ---
if [ -z "$SSH_USER" ] || [ -z "$SSH_SERVER" ]; then
    echo "⚠️  SSH_USER/SSH_SERVER not set — skipping SOCKS tunnel (set them in .env)"
else
echo "📦 Installing SOCKS proxy tunnel..."

if [ -n "$SSH_JUMP" ]; then
    if [[ ! "$SSH_JUMP" =~ ^[a-z_][a-z0-9_-]*@[A-Za-z0-9.-]+$ ]] ||
       [[ ! "$SSH_JUMP_HOST_KEY_SHA256" =~ ^SHA256:[A-Za-z0-9+/]+$ ]]; then
        echo "SSH_JUMP must be user@host and SSH_JUMP_HOST_KEY_SHA256 must be a SHA256 fingerprint" >&2
        exit 1
    fi
    JUMP_HOST="${SSH_JUMP#*@}"
    # Verify before replacing the running service. A key mismatch leaves the
    # existing tunnel untouched; ssh-keyscan alone is not authentication.
    JUMP_HOST_KEY="$(ssh-keyscan -T 5 -t ed25519 "$JUMP_HOST" 2>/dev/null | awk '$2 == "ssh-ed25519" { print; exit }')"
    if [ -z "$JUMP_HOST_KEY" ]; then
        echo "Could not read the jump host ED25519 key" >&2
        exit 1
    fi
    JUMP_FINGERPRINT="$(printf '%s\n' "$JUMP_HOST_KEY" | ssh-keygen -lf - | awk '{ print $2 }')"
    if [ "$JUMP_FINGERPRINT" != "$SSH_JUMP_HOST_KEY_SHA256" ]; then
        echo "Jump host key fingerprint mismatch; tunnel left unchanged" >&2
        exit 1
    fi
    printf '%s\n' "$JUMP_HOST_KEY" > "$SCRIPTS_DIR/tunnel-jump-known-hosts"
    chmod 600 "$SCRIPTS_DIR/tunnel-jump-known-hosts"

    cat > "$SCRIPTS_DIR/tunnel-proxy-jump.sh" << 'JUMP_EOF'
#!/bin/sh
# Only the SSH transport to the destination travels through the jump host.
exec ssh -q -i "SSH_KEY_PLACEHOLDER" \
    -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="JUMP_KNOWN_HOSTS_PLACEHOLDER" \
    -o ConnectTimeout=10 -o ConnectionAttempts=1 \
    -W "$1:$2" SSH_JUMP_PLACEHOLDER
JUMP_EOF
    sed -i '' "s|SSH_KEY_PLACEHOLDER|$SSH_KEY_FILE|g" "$SCRIPTS_DIR/tunnel-proxy-jump.sh"
    sed -i '' "s|JUMP_KNOWN_HOSTS_PLACEHOLDER|$SCRIPTS_DIR/tunnel-jump-known-hosts|g" "$SCRIPTS_DIR/tunnel-proxy-jump.sh"
    sed -i '' "s|SSH_JUMP_PLACEHOLDER|$SSH_JUMP|g" "$SCRIPTS_DIR/tunnel-proxy-jump.sh"
    chmod 700 "$SCRIPTS_DIR/tunnel-proxy-jump.sh"

    cat > "$SCRIPTS_DIR/tunnel-proxy.sh" << 'SCRIPT_EOF'
#!/bin/sh
exec ssh -D SOCKS_PORT_PLACEHOLDER -q -C -N \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=2 \
    -o ExitOnForwardFailure=yes -o TCPKeepAlive=yes \
    -o ConnectTimeout=10 -o ConnectionAttempts=1 \
    -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
    -o "ProxyCommand=JUMP_HELPER_PLACEHOLDER %h %p" \
    -i "SSH_KEY_PLACEHOLDER" SSH_USER_PLACEHOLDER@SSH_SERVER_PLACEHOLDER
SCRIPT_EOF
    sed -i '' "s|JUMP_HELPER_PLACEHOLDER|$SCRIPTS_DIR/tunnel-proxy-jump.sh|g" "$SCRIPTS_DIR/tunnel-proxy.sh"
else
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
fi

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
echo "For the HTTP proxy (gost), run: make install-http-proxy"
