#!/bin/sh
# xfsnap installer — POSIX sh, safe to pipe:  curl -fsSL <url>/install.sh | sh
#
# Env overrides:
#   PREFIX=/usr/local/bin   install location
#   XFSNAP_REPO=owner/repo   XFSNAP_BRANCH=main   source on GitHub
#   XFSNAP_SRC=/path/to/xfsnap   install from a local file instead of downloading
set -eu

REPO="${XFSNAP_REPO:-bernieblume/xfsnap}"
BRANCH="${XFSNAP_BRANCH:-main}"
PREFIX="${PREFIX:-/usr/local/bin}"
URL="https://raw.githubusercontent.com/$REPO/$BRANCH/xfsnap"
TARGET="$PREFIX/xfsnap"

say() { printf '%s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if [ -n "${XFSNAP_SRC:-}" ]; then
  say "installing xfsnap from local $XFSNAP_SRC"
  cp -- "$XFSNAP_SRC" "$TMP"
elif command -v curl >/dev/null 2>&1; then
  say "downloading xfsnap from $URL"
  curl -fsSL "$URL" -o "$TMP" || die "download failed"
elif command -v wget >/dev/null 2>&1; then
  say "downloading xfsnap from $URL"
  wget -qO "$TMP" "$URL" || die "download failed"
else
  die "need curl or wget to download xfsnap"
fi

# sanity: does it look like our script?
head -n 3 "$TMP" | grep -q xfsnap || die "downloaded file doesn't look like xfsnap"
chmod +x "$TMP"

if [ -w "$PREFIX" ]; then
  mv -f "$TMP" "$TARGET"
else
  say "installing to $TARGET (using sudo)"
  sudo mv -f "$TMP" "$TARGET" || die "install to $TARGET failed"
fi
trap - EXIT

say "installed: $("$TARGET" version 2>/dev/null || echo xfsnap) -> $TARGET"
say ""
say "next steps:"
say "  1) xfsnap config interview     # set up this host (snapshot dirs + peer)"
say "  2) do the same on the peer host"
say "  3) xfsnap doctor               # verify both ends are ready, then: xfsnap put"
