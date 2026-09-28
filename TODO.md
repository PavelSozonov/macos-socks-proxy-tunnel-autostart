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
