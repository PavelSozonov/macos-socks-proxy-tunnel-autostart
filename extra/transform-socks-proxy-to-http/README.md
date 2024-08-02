# Transform SOCKS proxy to HTTP proxy

Useful, e.g., for Docker Desktop, whose free version does not support SOCKS proxy

The setup has been tested on macOS Sonoma 14.5  (Apple Silicon).

### Prerequisite
SOCKS proxy is accessible via socks://127.0.0.1:8090

## Files

### 1. `pproxy.sh`

This script runs translator from SOCKS to ssh PROXY.

Save it at `/Users/<your-user>/scripts/pproxy.sh`.

### 2. `pproxy.plist`

This property list file configures launchctl to manage the SSH tunnel script.

Save it at `/Users/<your-user>/Library/LaunchAgents/pproxy.plist`.

### 3. `install-requirements.sh`

This script is installing requirement package `pproxy`

## Instructions

### 1. Install requirements
```sh
sh ./install-requirements.sh
```

### 2. Place the files to correct location

### 2. Ensure the script is executable
```sh
chmod +x /Users/<your-user>/scripts/pproxy.sh
```

### 3. Load the Launch Agent
```sh
launchctl load /Users/<your-user>/Library/LaunchAgents/pproxy.plist
```

### 4. Verify the Tranlator work
To verify if the translator `pproxy` is running, check the log files specified in the .plist file.
```sh
tail -f /Users/<your-user>/scripts/pproxy.log
tail -f /Users/<your-user>/scripts/pproxy-stderr.log
```

## Notes
* Replace all `<your-user>` placeholders with your actual username.
* The HTTP proxy will automatically start at system boot and will be kept alive by launchctl.
* HTTP proxy will be accessible via address `http://127.0.0.1:8091`.