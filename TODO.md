# TODO

Open items that are not work yet. Delete an entry when it is done or rejected;
the reason lives in the commit that closes it.

## Proposal: carry the SOCKS proxy over UDP (QUIC) instead of `ssh -D`

**Status: proposal. Assess the risks below before implementing anything.**

**Why.** `ssh -D` multiplexes every proxied connection into one TCP stream. On a
lossy link one lost packet stalls all of them until it is retransmitted
(head-of-line blocking), which is why a working tunnel was seen taking 1–6 s for
a single TLS handshake while the link lost a few percent of packets and its
round-trip time jumped from ~6 ms to 375 ms at the first provider hop. A
QUIC-based tunnel (e.g. a hysteria client exposing a local SOCKS port) keeps
proxied streams independent and recovers from loss without stalling them all.
Relaxing the watchdog removed the false restarts; it did not remove the stalls.

**Risks to assess first.**

- **UDP may fare worse, not better, on the same path.** Some networks throttle
  or drop UDP/QUIC to foreign addresses more aggressively than TCP. That has to
  be measured on the actual link, not assumed.
- **Server side.** The server needs a QUIC endpoint for this client: a separate
  account, port and credentials, and a firewall opening. It must not widen
  access for anyone else, and it must not share credentials with other users of
  the same endpoint.
- **Weaker access model.** Today access is one SSH key with a least-privilege
  account (see `docs/server-setup.md`). A shared-secret or password-based QUIC
  protocol is a different trust model; revocation and rotation need a plan.
- **More moving parts on the Mac.** A third-party binary to install, pin and
  update, its own launchd agent, and a watchdog that has to understand it. Keep
  `ssh -D` as a fallback rather than replacing it outright.
- **Battery and radio.** QUIC keepalives may keep the radio busier than SSH's.

**How to decide.** Run both side by side for a day or more on the real link:
the same watchdog check against each SOCKS port, counting failed checks and the
check's latency distribution. Switch only if the QUIC tunnel fails measurably
less often on that link.

## Remove the gost nightly workaround once Homebrew ships a fixed release

**Status: waiting on upstream. Homebrew has gost 3.3.0; nothing to do until a
newer version appears there.**

**What is in the repo now.** gost 3.3.0 crashes at startup on Apple M5 Pro /
M5 Max (go-m1cpu 0.1.6, see README "gost crashes on M5 Pro / M5 Max"). The
workaround is a nightly build installed by hand in place of the Homebrew one.
`scripts/check-gost.sh` runs `gost -V` before installing and prints the nightly
instructions when it crashes; the README section repeats them.

**When a release newer than 3.3.0 lands in Homebrew:**

1. Confirm the fix is in: its `go.mod` must list `github.com/shoenig/go-m1cpu`
   at v0.2.1 or newer (master already does). Then verify on an M5 Pro or M5 Max
   that `brew install gost && gost -V` prints the version instead of a
   `SIGSEGV` in `go-m1cpu._Cfunc_initialize`.
2. Keep the `gost -V` check in `scripts/check-gost.sh` — it is cheap and would
   catch the next crash-at-init — but replace the nightly instructions in its
   crash message with a plain "run brew upgrade gost, then retry".
3. Drop the README subsection "gost crashes on M5 Pro / M5 Max", or shrink it
   to one line saying the bug was in 3.3.0 and is fixed from the new version
   on, so people who pinned the nightly know to switch back with
   `rm /opt/homebrew/bin/gost && brew install gost`.
4. Anyone running the nightly should do that switch; it is not tracked by
   Homebrew, so `brew upgrade` will not replace it.

## Versioning: semantic versions, a `--version` and a changelog

**Status: planned.**

**Why.** There are no tags or releases today: an installed copy is whatever
`main` was checked out when `make install` ran, and nothing on the Mac says
which one. A bug report cannot name a version, and an update has nothing to
compare against.

**What.**

- Semantic versions (`MAJOR.MINOR.PATCH`) with annotated git tags `vX.Y.Z` on
  `main`; the first tag marks the current behaviour as `v1.0.0`.
- A `VERSION` file in the repo, kept equal to the latest tag; a CI check fails
  a release tag that does not match it.
- The installers write the version into the generated `~/scripts/*.sh` and
  into a small `~/scripts/tunnel-version` file; `make version` (and
  `--version` on the scripts that take arguments) prints the repo version and
  the installed one, so a mismatch is visible.
- `CHANGELOG.md` in the Keep a Changelog format; every release section lists
  user-visible changes and anything that needs a manual step (a new `.env`
  variable, a new Homebrew dependency).

## `make update`: update an installed copy to the latest release

**Status: planned, after versioning.**

**Why.** Updating today means `git pull` and re-running the right `make
install-*` targets by hand, and remembering which parts were installed. A
partly applied update can leave the tunnel down.

**What.**

1. `make update` fetches tags, finds the latest release newer than the
   installed version (from `~/scripts/tunnel-version`) and stops with a
   message if there is none or the working tree has local changes.
2. It checks out that tag and re-runs the installers only for the services
   that are installed now (as `make status` sees them), so it never adds a
   part the user did not choose.
3. `.env`, the SSH key and the server account are left as they are; new
   `.env` variables come with defaults and are listed from `CHANGELOG.md`.
4. Before touching anything it copies the current `~/scripts/*.sh` and the
   `~/Library/LaunchAgents/*.plist` of this repo to a backup directory.
   After reinstalling it runs the same check as `make check`; if the tunnel
   does not pass within the watchdog window it restores the backup, reloads
   the LaunchAgents, checks out the previous tag and reports the failure.
5. `make update TAG=vX.Y.Z` pins a specific release (also the way to roll
   back on purpose).

**Open.** Whether to check for a newer release on its own (for example, a
weekly notice in the watchdog log) or only when the user runs `make update`.
