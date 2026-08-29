#!/bin/bash

echo "🗑️  Uninstalling tunnel watchdog..."

DOMAIN_TARGET="gui/$(id -u)"

launchctl bootout "$DOMAIN_TARGET/tunnel-watchdog" 2>/dev/null || true

rm -f ~/Library/LaunchAgents/tunnel-watchdog.plist
rm -f ~/scripts/tunnel-watchdog.sh
rm -f ~/scripts/tunnel-watchdog.log
rm -f ~/scripts/tunnel-watchdog.state

echo "✅ Done"
