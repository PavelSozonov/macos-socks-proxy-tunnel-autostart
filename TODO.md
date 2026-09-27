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
