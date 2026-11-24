#!/usr/bin/env bash
# Puts ProTech's icons into the macOS build (run on a Mac, after assemble-source.sh --mac and before building):
#   * the app icon: AppIcon.icns, made from branding/mac/AppIcon.iconset with Apple's own `iconutil`
#   * the two menu-bar "template" images that are compiled into the program (res/mac-tray-*.png)
#   scripts/brand-mac.sh <source-tree>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:?usage: brand-mac.sh <source-tree>}"
[ -d "$SRC/flutter/macos/Runner" ] || { echo "$SRC is not a RustDesk source tree" >&2; exit 1; }
iconutil -c icns "$HERE/branding/mac/AppIcon.iconset" -o "$SRC/flutter/macos/Runner/AppIcon.icns"
cp "$HERE/branding/mac/tray/mac-tray-dark-x2.png"  "$SRC/res/mac-tray-dark-x2.png"
cp "$HERE/branding/mac/tray/mac-tray-light-x2.png" "$SRC/res/mac-tray-light-x2.png"
echo "branded: $(ls -l "$SRC/flutter/macos/Runner/AppIcon.icns" | awk '{print $5}') byte icon, 2 menu-bar images"
