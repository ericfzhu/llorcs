#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-release}"
APP="$ROOT/build/llorcs.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DMG="$ROOT/build/llorcs-$VERSION.dmg"
STAGING="$(mktemp -d /tmp/llorcs-dmg.XXXXXX)"

cleanup() {
    rm -rf "$STAGING"
}
trap cleanup EXIT

"$ROOT/scripts/build-app.sh" "$CONFIGURATION"

/usr/bin/ditto "$APP" "$STAGING/llorcs.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
/usr/bin/hdiutil create \
    -volname "llorcs" \
    -srcfolder "$STAGING" \
    -format UDZO \
    -ov \
    "$DMG"

print "$DMG"
