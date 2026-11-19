#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Remove helper + app and hand the LED back to the firmware.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

LABEL=com.moyer.magsafeledd
HELPER=/Library/PrivilegedHelperTools/magsafeledd

launchctl bootout system/$LABEL 2>/dev/null || true
[[ -x $HELPER ]] && "$HELPER" --write ACLC 00 || true
rm -f "/Library/LaunchDaemons/$LABEL.plist" "$HELPER"
rm -rf "/Library/Application Support/MagSafeLED" /Applications/MagSafeLED.app
pkill -x MagSafeLED 2>/dev/null || true
echo "Uninstalled; LED is back under firmware control."
