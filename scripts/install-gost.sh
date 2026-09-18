#!/bin/bash
set -e

# Standalone installer for gost HTTP-to-SOCKS proxy bridge
# Pre-requisite: brew install gost

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Load config (optional — defaults will be used if .env is missing)
if [ -f "$REPO_DIR/.env" ]; then
    source "$REPO_DIR/.env"
fi

# Defaults
SOCKS_PORT="${SOCKS_PORT:-8090}"
GOST_HTTP_PORT="${GOST_HTTP_PORT:-8118}"
# Bind address for the HTTP bridge.  Loopback by default: the bridge has no
# authentication, so exposing it on every interface makes an open proxy.
GOST_BIND="${GOST_BIND:-127.0.0.1}"
# Log level.  gost logs one line per proxied request at "info" — roughly 1.4 KB,
# including the destination host — so a busy day produced ~125 MB.  At "warn"
# only failures are recorded (this binary emits no warn-level events at all,
# so the tier is free), which measured at 7% of the volume.
GOST_LOG_LEVEL="${GOST_LOG_LEVEL:-warn}"

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

# The log level cannot be lowered with a flag (-D/-DD only raise it), so the
# bridge is configured with a file.  This config is the -O yaml serialisation of
# the former flags plus the log section.
cat > "$SCRIPTS_DIR/gost-proxy.yml" << EOF
log:
  level: $GOST_LOG_LEVEL
  format: json
services:
  - name: service-0
    addr: $GOST_BIND:$GOST_HTTP_PORT
    handler:
      type: http
      chain: chain-0
    listener:
      type: tcp
chains:
  - name: chain-0
    hops:
      - name: hop-0
        nodes:
          - name: node-0
            addr: 127.0.0.1:$SOCKS_PORT
            connector:
              type: socks5
            dialer:
              type: tcp
EOF

cat > "$SCRIPTS_DIR/gost-proxy.sh" << EOF
#!/bin/sh
exec $GOST_PATH -C $SCRIPTS_DIR/gost-proxy.yml
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

echo "✅ HTTP proxy (gost) installed: http://$GOST_BIND:$GOST_HTTP_PORT → socks5://127.0.0.1:$SOCKS_PORT (log level: $GOST_LOG_LEVEL)"
echo ""
echo "Useful commands:"
echo "  Status:   launchctl print gui/\$(id -u)/gost-proxy"
echo "  Logs:     tail -f ~/scripts/gost-proxy.log"
echo "  Stop:     launchctl kill TERM gui/\$(id -u)/gost-proxy"
echo "  Restart:  launchctl kickstart -k gui/\$(id -u)/gost-proxy"
