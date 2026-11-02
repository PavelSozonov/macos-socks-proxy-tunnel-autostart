# Repository workflow

Read [README.md](README.md) before changing the scripts. For server-side
security assumptions, also read [docs/server-setup.md](docs/server-setup.md).
Keep documentation, comments and commit messages in English, with no
attribution trailers. Use placeholders instead of personal configuration.

## Preserve the connection and security model

- Keep server, user, key and port settings in gitignored local configuration.
  Never copy real connection details, credentials or keys into tracked
  files, examples, logs or commit messages.
- The SSH SOCKS tunnel, HTTP-to-SOCKS bridge, watchdog and log cap are
  separate launchd components. Preserve their independent installation
  and removal paths.
- Keep the local proxy listeners on loopback. The HTTP bridge must forward
  through SOCKS; substituting a direct-to-internet proxy changes the
  security model.
- Preserve the missing-or-crashing `gost` check before installation changes
  begin. Do not leave a partially installed setup when that check fails.
- With an SSH relay, verify its configured host-key fingerprint before
  replacing or restarting the tunnel. Preserve the destination's existing
  `known_hosts` verification and the configured proxy ports.
- Preserve the server guide's least-privilege forwarding-only account
  assumptions. Do not add shell, command, agent or X11 access as a shortcut.

## Preserve recovery and logging behavior

- The watchdog checks real traffic through the SOCKS path rather than
  trusting that an SSH process exists. It does nothing when the tunnel
  service is not loaded.
- Keep the documented AC and battery timing choices, failure threshold,
  timeout and reconnect pause consistent. Their measured recovery and
  false-restart trade-offs are documented in the README.
- Keep bridge logging at the documented warning level, with successful
  requests omitted. Avoid retaining browsing destinations unnecessarily.
- Cap logs by truncating them in place, preserving the open-file behavior
  of launchd and a bounded previous tail. Do not silently replace this with
  rename-based rotation or unbounded archives.

## Checks and handoff

Run `make lint` or `pre-commit run --all-files` for the existing lint suite.
Keep the pinned hook versions and `.github/workflows/ci.yml` in sync when
changing checks. CI runs lint hooks and a secret scan; do not invent an
additional test or deployment result.

Installation, uninstallation, restarts and live proxy health checks act on
an actual machine. Do not run them as validation for repository-only work.
Report the checks performed and distinguish static validation from testing
an installed tunnel.
