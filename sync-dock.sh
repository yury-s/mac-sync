#!/usr/bin/env bash
#
# sync-dock.sh — replicate the macOS Dock layout from the old mac.
#
# Run this ON THE NEW MAC. It pulls ~/Library/Preferences/com.apple.dock.plist
# from the old mac over SSH and restarts the Dock.
#
# USAGE:
#   OLDHOST=<oldhost> ./sync-dock.sh
#
# Run it AFTER your apps are installed (e.g. the brew phase of setup-new-mac.sh),
# otherwise dock entries for missing apps show up as a "?" placeholder.

set -uo pipefail

OLDHOST="${OLDHOST:-CHANGE_ME}"
PLIST="$HOME/Library/Preferences/com.apple.dock.plist"

if [ "$OLDHOST" = "CHANGE_ME" ]; then
  echo "ERROR: set OLDHOST (e.g. OLDHOST=myoldmac ./sync-dock.sh)" >&2
  exit 1
fi

echo "==> Pulling Dock layout from $OLDHOST"
if rsync -azP "$OLDHOST:~/Library/Preferences/com.apple.dock.plist" \
      "$HOME/Library/Preferences/" 2>/dev/null; then
  defaults import com.apple.dock "$PLIST" 2>/dev/null
  killall Dock 2>/dev/null
  echo "    Dock layout applied and restarted."
  echo "    (Any app not installed yet will show as '?' until you install it.)"
else
  echo "ERROR: could not pull com.apple.dock.plist from $OLDHOST" >&2
  exit 1
fi
