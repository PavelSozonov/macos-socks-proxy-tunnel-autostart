# Auto-Starting SSH Tunnel with SOCKS Proxy on macOS using launchctl

This guide provides instructions on how to configure an SSH tunnel with a SOCKS proxy to auto-start on macOS using `launchctl`.

The setup has been tested on macOS Sonoma 14.5  (Apple Silicon).

## Prerequisite

Configure SSH connection to your Linux server via SSH key (out of scope of this instruction).

Assume that key is located at `/Users/<your-user>/.ssh/id_ed25519`


## Files

### 1. `tunnel-proxy.sh`

This script establishes the SSH tunnel. 

Save it at `/Users/<your-user>/scripts/tunnel-proxy.sh`.

### 2. `tunnel-proxy.plist`

This property list file configures launchctl to manage the SSH tunnel script. 

Save it at `/Users/<your-user>/Library/LaunchAgents/tunnel-proxy.plist`.

### 3. `bootstrap.sh`

This script automatically performs all manual actions described in this instruction.

Use it carefully, before running set correct variable's values and check it's instructions. 

## Instructions

### 1. Place the files to correct location

### 2. Ensure the script is executable
```sh
chmod +x /Users/<your-user>/scripts/tunnel-proxy.sh
```

### 3. Load the Launch Agent
```sh
launchctl load /Users/<
```

### 4. Verify the Tunnel
To verify if the tunnel is running, check the log files specified in the .plist file.
```sh
tail -f /Users/<your-user>/scripts/tunnel-proxy.log
tail -f /Users/<your-user>/scripts/tunnel-proxy-stderr.log
```

## Notes
* Replace all `<your-user>`, `<user>`, and `<server-address>` placeholders with your actual username, SSH user, and the foreign server address, respectively.
* Ensure your SSH key is correctly placed at `/Users/<your-user>/.ssh/id_ed25519` and is accessible.
* The tunnel will automatically start at system boot and will be kept alive by launchctl.

This setup ensures your SSH tunnel with SOCKS proxy is consistently running, providing a stable and persistent proxy connection.

## Using SOCKS proxy with a web browser
This solution can be used (and tested) with Chrome browser SwitchyOmega plugin (there are alternatives also).

### Configuration for SwitcyOmega plugin
1. Go to the plugin settings, create new profile and add proxy server
```
Scheme: default
Protocol: SOCKS4
Server: 127.0.0.1
Port: 8090
```
2. Go to auto-switch section and add new rule(s)
```
Condition Type: Host wildcard
Condition Details: *.linkedin.com (or any domain which need to be served via SOCKS proxy)
Profile: <your-profile-name> (name of the profile created in the first step)
```
3. Click `Apply changes` button
4. Click on the plugin icon (at the plugin bar in the browser) and choose `auto-switch` mode