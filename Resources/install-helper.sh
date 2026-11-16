#!/bin/sh
# Installs the FermataNeo root helper. Must run as root.
# Usage: install-helper.sh <helper binary> <launchd plist>
set -e

LABEL=local.FermataNeo.Helper
BIN=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist

/bin/launchctl bootout system/$LABEL 2>/dev/null || true

/bin/mkdir -p /Library/PrivilegedHelperTools
# Remove first: overwriting a signed binary in place can get it killed on launch.
/bin/rm -f "$BIN" "$PLIST"
/bin/cp "$1" "$BIN"
/bin/cp "$2" "$PLIST"
/usr/sbin/chown root:wheel "$BIN" "$PLIST"
/bin/chmod 755 "$BIN"
/bin/chmod 644 "$PLIST"

/bin/launchctl bootstrap system "$PLIST"
