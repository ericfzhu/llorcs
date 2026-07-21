#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-release}"
APP="$ROOT/build/llorcs.app"
MODULE_CACHE="$ROOT/.build/module-cache"
SIGNING_IDENTITY="${LLORCS_SIGNING_IDENTITY:-}"
ARCHITECTURES=("${(@s: :)${LLORCS_ARCHITECTURES:-arm64 x86_64}}")

cd "$ROOT"
mkdir -p "$ROOT/build" "$MODULE_CACHE"

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
BINARIES=()

for architecture in "${ARCHITECTURES[@]}"; do
    STAGING="$ROOT/.build/llorcs-$CONFIGURATION-$architecture"
    ARCH_MODULE_CACHE="$MODULE_CACHE/$architecture"
    TARGET="$architecture-apple-macosx13.0"
    mkdir -p "$STAGING" "$ARCH_MODULE_CACHE"

    CLANG_MODULE_CACHE_PATH="$ARCH_MODULE_CACHE" swiftc \
        -sdk "$SDK" \
        -target "$TARGET" \
        -parse-as-library \
        -emit-library -static \
        -emit-module -module-name LlorcsCore \
        -emit-module-path "$STAGING/LlorcsCore.swiftmodule" \
        "${OPTIMIZATION[@]}" \
        "${CORE_SOURCES[@]}" \
        -framework ApplicationServices -framework IOKit -framework ServiceManagement \
        -o "$STAGING/libLlorcsCore.a"

    CLANG_MODULE_CACHE_PATH="$ARCH_MODULE_CACHE" swiftc \
        -sdk "$SDK" \
        -target "$TARGET" \
        -parse-as-library \
        -I "$STAGING" -L "$STAGING" \
        "${OPTIMIZATION[@]}" \
        "${APP_SOURCES[@]}" \
        -lLlorcsCore \
        -framework AppKit -framework SwiftUI \
        -framework ApplicationServices -framework IOKit -framework ServiceManagement \
        -o "$STAGING/llorcs"

    BINARIES+=("$STAGING/llorcs")
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/llorcs"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

if [[ -z "$SIGNING_IDENTITY" ]]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -Fq '"llorcs Local Signing"'; then
        SIGNING_IDENTITY="llorcs Local Signing"
    else
        SIGNING_IDENTITY="-"
        print -u2 "No local signing certificate found; using an ad hoc signature."
    fi
fi

codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"

print "$APP"
