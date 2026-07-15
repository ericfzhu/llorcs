#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-release}"
APP="$ROOT/build/llorcs.app"
STAGING="$ROOT/.build/llorcs-$CONFIGURATION"
MODULE_CACHE="$ROOT/.build/module-cache"
SIGNING_IDENTITY="${LLORCS_SIGNING_IDENTITY:-llorcs Local Signing}"

cd "$ROOT"
mkdir -p "$STAGING" "$MODULE_CACHE"

# Pick the first installed SDK the active compiler can import. This also handles
# machines where the default SDK symlink was updated ahead of the compiler.
SDK=""
for candidate in /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk(N) \
                 /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk(N) \
                 /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk(N); do
    if print 'import Foundation' | CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
        swiftc -sdk "$candidate" -typecheck - >/dev/null 2>&1; then
        SDK="$candidate"
        break
    fi
done

if [[ -z "$SDK" ]]; then
    print -u2 "No macOS SDK compatible with the active Swift compiler was found."
    exit 1
fi

CORE_SOURCES=(Sources/LlorcsCore/*.swift)
APP_SOURCES=(Sources/LlorcsApp/*.swift)
OPTIMIZATION=(-O)
[[ "$CONFIGURATION" == "debug" ]] && OPTIMIZATION=(-Onone -g)

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
    -sdk "$SDK" \
    -parse-as-library \
    -emit-library -static \
    -emit-module -module-name LlorcsCore \
    -emit-module-path "$STAGING/LlorcsCore.swiftmodule" \
    "${OPTIMIZATION[@]}" \
    "${CORE_SOURCES[@]}" \
    -framework ApplicationServices -framework IOKit -framework ServiceManagement \
    -o "$STAGING/libLlorcsCore.a"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
    -sdk "$SDK" \
    -parse-as-library \
    -I "$STAGING" -L "$STAGING" \
    "${OPTIMIZATION[@]}" \
    "${APP_SOURCES[@]}" \
    -lLlorcsCore \
    -framework AppKit -framework SwiftUI \
    -framework ApplicationServices -framework IOKit -framework ServiceManagement \
    -o "$STAGING/llorcs"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$STAGING/llorcs" "$APP/Contents/MacOS/llorcs"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"

print "$APP"
