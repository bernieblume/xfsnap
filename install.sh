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
  say "Installing xfsnap from local $XFSNAP_SRC"
  cp -- "$XFSNAP_SRC" "$TMP"
elif command -v curl >/dev/null 2>&1; then
  say "Downloading xfsnap from $URL"
  curl -fsSL "$URL" -o "$TMP" || die "Download failed"
elif command -v wget >/dev/null 2>&1; then
  say "Downloading xfsnap from $URL"
  wget -qO "$TMP" "$URL" || die "Download failed"
else
  die "Need curl or wget to download xfsnap"
fi

# sanity: does it look like our script?
head -n 3 "$TMP" | grep -q xfsnap || die "Downloaded file doesn't look like xfsnap"
# explicit 0755: mktemp makes it 0600, and `chmod +x` on that can yield a
# root-only 0700 under sudo -- other users then can't run it.
chmod 0755 "$TMP"

if [ -w "$PREFIX" ]; then
  mv -f "$TMP" "$TARGET"
else
  say "Installing to $TARGET (using sudo)"
  sudo mv -f "$TMP" "$TARGET" || die "Install to $TARGET failed"
fi
trap - EXIT

say "Installed: $("$TARGET" version 2>/dev/null || echo xfsnap) -> $TARGET"
say ""

# Offer to run setup now -- but only with a real terminal. With `curl | sh`,
# stdin is the pipe, so we read the user from /dev/tty; when piped in CI (no
# tty) we skip straight to the printed next-steps and never block.
if [ -t 1 ] && [ -r /dev/tty ]; then
  printf 'Set up this host now (xfsnap config interview)? [Y/n]: ' > /dev/tty
  ans=''
  read ans < /dev/tty || ans=''
  case "${ans:-Y}" in
    [nN]*) : ;;
    *) exec "$TARGET" config interview < /dev/tty ;;   # hand off (incl. peer wizard)
  esac
fi

say "Next steps:"
say "  1) xfsnap config interview   # Set up this host -- it then offers to install"
say "                               #   xfsnap on your peer(s) and set them up too"
say "  2) xfsnap doctor             # Verify both ends, then:  xfsnap put"
