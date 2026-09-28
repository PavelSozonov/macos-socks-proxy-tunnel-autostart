#!/bin/bash
# Verifies that gost is installed AND starts on this Mac, before anything is
# installed.  Prints the path to the working binary on stdout; every message
# goes to stderr.  Exits 1 with an explanation when gost is missing or crashes.
#
# The crash check exists because gost 3.3.0 from Homebrew dies at startup on
# Apple M5 Pro / M5 Max: its go-m1cpu 0.1.6 dependency reads a CPU-frequency
# property from IOKit that those chips do not expose, and dereferences the
# missing value.  The crash happens in package init, before any flag or config
# is read, so the launchd service would restart it every 5 seconds forever
# while port 8118 stays closed.  `gost -V` trips the same init, so it is a
# cheap and exact test.  Fixed upstream in go-m1cpu 0.2.1, shipped in gost
# nightly builds since 2026-09-13; see README "gost crashes on M5 Pro / M5 Max".

find_gost() {
    command -v gost 2>/dev/null && return
    for p in /opt/homebrew/bin/gost /usr/local/bin/gost; do
        [ -x "$p" ] && echo "$p" && return
    done
}

GOST_PATH=$(find_gost)

if [ -z "$GOST_PATH" ]; then
    cat >&2 <<'MSG'
❌ gost is not installed. It provides the HTTP proxy and is required.
   Install it, then run make again:

       brew install gost

MSG
    exit 1
fi

if ! "$GOST_PATH" -V >/dev/null 2>&1; then
    CHIP=$(/usr/sbin/sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "unknown chip")
    cat >&2 <<MSG
❌ gost is installed at $GOST_PATH but crashes on startup on this Mac ($CHIP).
   Nothing was installed: as a launchd service it would crash every 5 seconds
   and port 8118 would never open.

   This is a known bug in gost 3.3.0 and earlier on Apple M5 Pro / M5 Max: a
   dependency (go-m1cpu 0.1.6) reads a CPU property these chips do not have.
   Homebrew has no fixed release yet; the fix is in the gost nightly builds.

   Install a nightly build in place of the Homebrew one:

       brew uninstall gost
       cd ~/Downloads
       curl -sSLO https://github.com/go-gost/gost/releases/download/v3.3.1-nightly.20260922/gost_3.3.1-nightly.20260922_darwin_arm64.tar.gz
       tar xzf gost_3.3.1-nightly.20260922_darwin_arm64.tar.gz gost
       mv gost /opt/homebrew/bin/gost
       /opt/homebrew/bin/gost -V      # must print the version, not crash

   Newer nightlies: https://github.com/go-gost/gost/releases (darwin_arm64).
   Then run make again. See README, "gost crashes on M5 Pro / M5 Max".

MSG
    exit 1
fi

echo "$GOST_PATH"
