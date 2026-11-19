#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Build the helper and assemble build/MagSafeLED.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=$(swift build -c release --show-bin-path)

APP=build/MagSafeLED.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/MagSafeLED" "$APP/Contents/MacOS/MagSafeLED"
cp "$BIN/magsafeledd" build/magsafeledd

codesign --force --sign - build/magsafeledd
codesign --force --sign - "$APP"
echo "Built $APP and build/magsafeledd"
