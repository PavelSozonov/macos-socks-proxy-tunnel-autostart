#!/bin/bash

echo "🗑️  Uninstalling gost proxy..."

DOMAIN_TARGET="gui/$(id -u)"

launchctl bootout "$DOMAIN_TARGET/gost-proxy" 2>/dev/null || true

rm -f ~/Library/LaunchAgents/gost-proxy.plist
rm -f ~/scripts/gost-proxy.sh
rm -f ~/scripts/gost-proxy.log

echo "✅ Done"
