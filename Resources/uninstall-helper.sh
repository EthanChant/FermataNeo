#!/bin/sh
# Removes the FermataNeo root helper and restores normal sleep. Must run as root.

LABEL=local.FermataNeo.Helper

/bin/launchctl bootout system/$LABEL 2>/dev/null || true
/bin/rm -f /Library/PrivilegedHelperTools/$LABEL /Library/LaunchDaemons/$LABEL.plist
/usr/bin/pmset -a disablesleep 0
