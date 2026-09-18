#!/bin/bash
set -e

# Standalone installer for the log size cap.
#
# The launchd services here write to plain files through StandardOutPath, and
# gost logs one line per proxied request — roughly 1.4 KB — so the bridge log
# grows without bound (it was found at 3.3 GB).  This agent keeps each log under
# a limit.

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Load config (optional — defaults will be used if .env is missing)
if [ -f "$REPO_DIR/.env" ]; then
    source "$REPO_DIR/.env"
fi

# Defaults: 500 MiB per file, checked every 5 minutes
LOG_CAP_BYTES="${LOG_CAP_BYTES:-524288000}"
LOG_CAP_INTERVAL="${LOG_CAP_INTERVAL:-300}"

SCRIPTS_DIR="$HOME/scripts"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
DOMAIN_TARGET="gui/$(id -u)"

mkdir -p "$SCRIPTS_DIR" "$LAUNCH_AGENTS"

echo "📦 Installing log size cap (${LOG_CAP_BYTES} bytes per file)..."

cat > "$SCRIPTS_DIR/log-cap.sh" << 'SCRIPT'
#!/bin/sh
# Cap log files at a size limit by truncating them in place.
#
# Truncation, not rotation: launchd holds these files open through
# StandardOutPath/StandardErrorPath in O_APPEND mode.  Renaming would leave the
# service writing into the renamed file while the fresh one stayed empty until
# the next restart.  Truncating keeps the same inode, frees the space at once,
# and O_APPEND makes writes resume at offset 0 rather than leaving a sparse hole.
#
# Usage: log-cap.sh <limit-bytes> <file> [file ...]

limit="$1"
shift 2>/dev/null || { echo "usage: $0 <limit-bytes> <file> [file ...]" >&2; exit 64; }
case "$limit" in ''|*[!0-9]*) echo "limit must be a byte count" >&2; exit 64 ;; esac

for f in "$@"; do
    [ -f "$f" ] || continue
    size=$(stat -f%z "$f" 2>/dev/null) || continue
    if [ "$size" -gt "$limit" ]; then
        : > "$f"
        echo "$(date '+%Y-%m-%d %H:%M:%S') truncated $f (was $size bytes, limit $limit)"
    fi
done
SCRIPT
chmod +x "$SCRIPTS_DIR/log-cap.sh"

cat > "$LAUNCH_AGENTS/log-cap.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>log-cap</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPTS_DIR/log-cap.sh</string>
        <string>$LOG_CAP_BYTES</string>
        <string>$SCRIPTS_DIR/gost-proxy.log</string>
        <string>$SCRIPTS_DIR/tunnel-proxy.log</string>
        <string>$SCRIPTS_DIR/tunnel-watchdog.log</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>$LOG_CAP_INTERVAL</integer>
    <key>StandardOutPath</key>
    <string>$SCRIPTS_DIR/log-cap.log</string>
    <key>StandardErrorPath</key>
    <string>$SCRIPTS_DIR/log-cap.log</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF

# Load/reload the service
if launchctl print "$DOMAIN_TARGET/log-cap" &>/dev/null; then
    launchctl bootout "$DOMAIN_TARGET/log-cap" 2>/dev/null || true
    sleep 1
fi
launchctl bootstrap "$DOMAIN_TARGET" "$LAUNCH_AGENTS/log-cap.plist"

echo "✅ Log cap installed: every ${LOG_CAP_INTERVAL}s, each log truncated past ${LOG_CAP_BYTES} bytes"
echo ""
echo "Useful commands:"
echo "  Status:   launchctl print gui/\$(id -u)/log-cap"
echo "  Log:      tail -f ~/scripts/log-cap.log"
echo "  Run now:  launchctl kickstart -k gui/\$(id -u)/log-cap"
