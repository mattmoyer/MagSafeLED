#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Install the root helper as a LaunchDaemon and copy the app to /Applications.
# Run: sudo scripts/install.sh   (after scripts/build.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
[[ -f build/magsafeledd ]] || { echo "run scripts/build.sh first"; exit 1; }

LABEL=com.moyer.magsafeledd
PLIST=/Library/LaunchDaemons/$LABEL.plist

launchctl bootout system/$LABEL 2>/dev/null || true

install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
install -o root -g wheel -m 755 build/magsafeledd /Library/PrivilegedHelperTools/magsafeledd
install -o root -g wheel -m 644 Resources/$LABEL.plist "$PLIST"

launchctl bootstrap system "$PLIST"
echo "Helper installed and running: launchctl print system/$LABEL"

rm -rf /Applications/MagSafeLED.app
cp -R build/MagSafeLED.app /Applications/
chown -R "${SUDO_USER:-root}" /Applications/MagSafeLED.app
echo "App installed: open /Applications/MagSafeLED.app"
