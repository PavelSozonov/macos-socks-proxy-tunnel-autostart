#!/bin/bash

# Variables - Replace these with your actual details
USER="<your-user>"
SSH_USER="<user>"
SERVER_ADDRESS="<server-address>"
SCRIPTS_DIR="/Users/$USER/scripts"
PLIST_DIR="/Users/$USER/Library/LaunchAgents"
SCRIPT_FILE="$SCRIPTS_DIR/tunnel-proxy.sh"
PLIST_FILE="$PLIST_DIR/tunnel-proxy.plist"

# Create directories if they do not exist
mkdir -p "$SCRIPTS_DIR"
mkdir -p "$PLIST_DIR"

# Create tunnel-proxy.sh
cat <<EOL > "$SCRIPT_FILE"
#!/bin/sh

ssh -D 8090 -q -C -N -i /Users/$USER/.ssh/id_ed25519 $SSH_USER@$SERVER_ADDRESS
EOL

# Make the script executable
chmod +x "$SCRIPT_FILE"

# Create tunnel-proxy.plist
cat <<EOL > "$PLIST_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>tunnel-proxy</string>
    <key>ProgramArguments</key>
    <array>
       <string>/Users/$USER/scripts/tunnel-proxy.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>1</integer>
    <key>StandardOutPath</key>
    <string>/Users/$USER/scripts/tunnel-proxy.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/$USER/scripts/tunnel-proxy-stderr.log</string>
  </dict>
</plist>
EOL

# Load the launch agent
launchctl load "$PLIST_FILE"

echo "Setup complete. SSH tunnel with SOCKS proxy should now auto-start on macOS using launchctl."
