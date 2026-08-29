# Server Setup: a Least-Privilege SSH User for the Tunnel

The tunnel runs unattended from launchd, so its SSH key has to be usable without a passphrase.
If that key opens a normal shell account (or root), losing the laptop means losing the server.

This guide creates a server account that can do **only one thing: forward ports**.
No shell, no commands, no TTY, no agent/X11 forwarding, no password login.

Tested on Debian/Ubuntu; the RHEL/Fedora differences are noted inline.

## 1. Create a user without a shell

```bash
sudo useradd -m -s /usr/sbin/nologin tunnel      # Debian/Ubuntu
# sudo useradd -m -s /sbin/nologin tunnel        # RHEL/Fedora
```

The client always connects with `-N` (no remote command), so a `nologin` shell does not get in the way of the tunnel — it only blocks interactive logins.

## 2. Generate a dedicated key on your Mac

Use a separate key for this account, with no passphrase (launchd cannot type one):

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519_tunnel -C "socks-tunnel"
```

Point the installer at it in `.env`:

```
SSH_USER=tunnel
SSH_KEY_FILE=~/.ssh/id_ed25519_tunnel
```

## 3. Install the key with restrictions

On the server, add the **public** key (`~/.ssh/id_ed25519_tunnel.pub`) to the tunnel user's `authorized_keys`, prefixed with options that strip everything except port forwarding:

```bash
sudo install -d -m 700 -o tunnel -g tunnel /home/tunnel/.ssh
echo 'restrict,port-forwarding ssh-ed25519 AAAA...your-public-key... socks-tunnel' \
  | sudo tee /home/tunnel/.ssh/authorized_keys
sudo chmod 600 /home/tunnel/.ssh/authorized_keys
sudo chown tunnel:tunnel /home/tunnel/.ssh/authorized_keys
```

- `restrict` — disables PTY, agent forwarding, X11 forwarding, user-rc and, by itself, port forwarding
- `port-forwarding` — re-enables the one thing the tunnel needs

## 4. Lock it down in `sshd_config` as well

The `authorized_keys` options are per-key; a `Match` block enforces the same policy for the whole account, even if the file is later replaced:

```
# /etc/ssh/sshd_config.d/tunnel.conf   (or append to /etc/ssh/sshd_config)
Match User tunnel
    AllowTcpForwarding local
    PermitTTY no
    X11Forwarding no
    AllowAgentForwarding no
    PasswordAuthentication no
    PermitOpen any
```

- `AllowTcpForwarding local` — allows `-L`/`-D` (what we use) but not reverse tunnels (`-R`)
- `PermitOpen any` — SOCKS is dynamic, so destinations cannot be enumerated; narrow it (e.g. `PermitOpen 10.0.0.0/8:*`) if the proxy should only reach specific hosts

Apply:

```bash
sudo sshd -t && sudo systemctl reload ssh     # Debian/Ubuntu
# sudo sshd -t && sudo systemctl reload sshd  # RHEL/Fedora
```

## 5. Verify

From your Mac:

```bash
# Interactive login must be refused
ssh -i ~/.ssh/id_ed25519_tunnel tunnel@your-server.com
# -> connection closes immediately (nologin) / "PTY allocation request failed"

# Port forwarding must work
ssh -i ~/.ssh/id_ed25519_tunnel -N -D 1080 tunnel@your-server.com &
curl --socks5-hostname 127.0.0.1:1080 https://ifconfig.me   # prints the server's IP
kill %1
```

Then install the tunnel as usual: `make install`.

## What this does not protect against

The account can still open TCP connections *from the server* to anywhere `PermitOpen` allows — that is the purpose of a SOCKS proxy. Anyone holding the key can use your server as an exit node, so treat `id_ed25519_tunnel` like a password: keep it out of backups you don't control and rotate it (`ssh-keygen` + replace the line in `authorized_keys`) if the laptop is lost.
