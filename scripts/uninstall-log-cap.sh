#!/bin/bash

echo "🗑️  Uninstalling log size cap..."

DOMAIN_TARGET="gui/$(id -u)"

launchctl bootout "$DOMAIN_TARGET/log-cap" 2>/dev/null || true

rm -f ~/Library/LaunchAgents/log-cap.plist
rm -f ~/scripts/log-cap.sh
rm -f ~/scripts/log-cap.log

echo "✅ Done — the service logs themselves are left in place, uncapped"
