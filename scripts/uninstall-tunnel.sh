#!/bin/bash

echo "🗑️  Uninstalling proxy tunnel..."

DOMAIN_TARGET="gui/$(id -u)"

launchctl bootout "$DOMAIN_TARGET/tunnel-proxy" 2>/dev/null || true

rm -f ~/Library/LaunchAgents/tunnel-proxy.plist
rm -f ~/scripts/tunnel-proxy.sh
rm -f ~/scripts/tunnel-proxy.log

echo "✅ Done"
