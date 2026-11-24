#!/usr/bin/env bash
# Turns a freshly built RustDesk.app into the ProTech Support download for a Mac. Needs only what every Mac has (ditto, codesign, xattr),
# no Xcode, so it also runs on a customer-support Mac to re-pack an app with new settings in seconds.
#
#   scripts/package-mac.sh <RustDesk.app | built .zip> <output-dir> --arch arm64|x86_64 [--custom custom.txt]
#
#   1. renames the app to "ProTech Support.app"
#   2. with --custom: adds the signed settings file (Contents/Resources/custom.txt, where the program looks for it on a Mac)
#   3. signs every piece "ad hoc" (an Apple-chip Mac refuses to run completely unsigned code; ad hoc needs no Apple account) and checks it
#   4. writes ProTech-Support-<arch>.zip (a zip, not a disk image: Safari unpacks it by itself, so the customer double-clicks one app)
# The app is NOT notarised by Apple, so macOS asks the customer to approve it once (System Settings > Privacy & Security > Open Anyway).
set -euo pipefail

IN="${1:?usage: package-mac.sh <RustDesk.app|zip> <output-dir> --arch arm64|x86_64 [--custom custom.txt]}"; OUT="${2:?output dir}"; shift 2
ARCH=""; CUSTOM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --arch) ARCH="${2:?}"; shift 2 ;;
    --custom) CUSTOM="${2:?}"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
case "$ARCH" in arm64|x86_64) ;; *) echo "--arch must be arm64 or x86_64" >&2; exit 2 ;; esac
[ -z "$CUSTOM" ] || [ -s "$CUSTOM" ] || { echo "custom.txt not found: $CUSTOM" >&2; exit 2; }

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/protech-package.XXXXXX")"; trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
APP="$STAGE/ProTech Support.app"
if [ -d "$IN" ]; then ditto "$IN" "$APP"
else ditto -x -k "$IN" "$STAGE/x"; SRC="$(find "$STAGE/x" -maxdepth 1 -name '*.app' | head -1)"; [ -n "$SRC" ] || { echo "no .app inside $IN" >&2; exit 1; }; mv "$SRC" "$APP"; fi

[ -x "$APP/Contents/MacOS/RustDesk" ] || { echo "not a RustDesk build: Contents/MacOS/RustDesk is missing" >&2; exit 1; }
echo "== program: $(file -b "$APP/Contents/MacOS/RustDesk" | cut -c1-90)"
if [ -n "$CUSTOM" ]; then install -m 0644 "$CUSTOM" "$APP/Contents/Resources/custom.txt"; echo "== settings file added ($(wc -c < "$CUSTOM" | tr -d ' ') bytes)"; fi
xattr -cr "$APP"

echo "== signing (ad hoc)"
# inside-out: frameworks and libraries, then the helper programs, then the bundle itself
find "$APP/Contents/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) 2>/dev/null | while read -r f; do codesign --force --sign - --timestamp=none "$f"; done
for f in "$APP"/Contents/MacOS/*; do codesign --force --sign - --timestamp=none "$f"; done
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"
echo "== signature: $(codesign -dv "$APP" 2>&1 | grep -E 'Signature|Identifier' | tr '\n' ' ')"

ZIP="$OUT/ProTech-Support-$ARCH.zip"; rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
( cd "$OUT" && shasum -a 256 "ProTech-Support-$ARCH.zip" | tee "ProTech-Support-$ARCH.zip.sha256" )
echo "== done: $ZIP ($(du -h "$ZIP" | cut -f1))"
