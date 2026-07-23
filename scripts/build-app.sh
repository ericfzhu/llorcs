#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-release}"
APP="$ROOT/build/llorcs.app"
MODULE_CACHE="$ROOT/.build/module-cache"
SIGNING_IDENTITY="${LLORCS_SIGNING_IDENTITY:--}"
ARCHITECTURES=("${(@s: :)${LLORCS_ARCHITECTURES:-arm64 x86_64}}")

cd "$ROOT"
mkdir -p "$ROOT/build" "$MODULE_CACHE"

# Keep the compiler and SDK from the same developer installation. Mixing the
# active compiler with an SDK from another Xcode version can make Foundation
# impossible to import.
SWIFTC=""
SDK=""

try_toolchain() {
    local compiler="$1"
    local sdk="$2"

    [[ -x "$compiler" && -d "$sdk" ]] || return 1

    if print 'import Foundation' | CLANG_MODULE_CACHE_PATH="$MODULE_CACHE/toolchain-check" \
        "$compiler" -sdk "$sdk" -typecheck - >/dev/null 2>&1; then
        SWIFTC="$compiler"
        SDK="$sdk"
        return 0
    fi

    return 1
}

if [[ -n "${LLORCS_SWIFTC:-}" || -n "${LLORCS_SDK:-}" ]]; then
    if [[ -z "${LLORCS_SWIFTC:-}" || -z "${LLORCS_SDK:-}" ]] \
        || ! try_toolchain "$LLORCS_SWIFTC" "$LLORCS_SDK"; then
        print -u2 "LLORCS_SWIFTC and LLORCS_SDK must point to a compatible compiler and SDK."
        exit 1
    fi
else
    ACTIVE_SWIFTC="$(xcrun --find swiftc 2>/dev/null || true)"
    ACTIVE_SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
    try_toolchain "$ACTIVE_SWIFTC" "$ACTIVE_SDK" || true

    if [[ -z "$SWIFTC" ]]; then
        for developer_dir in /Applications/Xcode*.app/Contents/Developer(N); do
            compiler="$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
            for sdk in "$developer_dir"/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk(N); do
                if try_toolchain "$compiler" "$sdk"; then
                    break 2
                fi
            done
        done
    fi

    if [[ -z "$SWIFTC" ]]; then
        compiler="/Library/Developer/CommandLineTools/usr/bin/swiftc"
        for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk(N); do
            if try_toolchain "$compiler" "$sdk"; then
                break
            fi
        done
    fi
fi

if [[ -z "$SWIFTC" || -z "$SDK" ]]; then
    print -u2 "No compatible macOS Swift compiler and SDK pair was found."
    print -u2 "Install matching Xcode Command Line Tools, or set LLORCS_SWIFTC and LLORCS_SDK."
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

    CLANG_MODULE_CACHE_PATH="$ARCH_MODULE_CACHE" "$SWIFTC" \
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

    CLANG_MODULE_CACHE_PATH="$ARCH_MODULE_CACHE" "$SWIFTC" \
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

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    print -u2 "Using an ad hoc signature. Set LLORCS_SIGNING_IDENTITY for another identity."
fi

codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"

print "$APP"
