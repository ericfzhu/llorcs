#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE="$ROOT/Resources/AppIcon.png"
OUTPUT="$ROOT/Resources/AppIcon.icns"
WORK="$(mktemp -d /tmp/llorcs-icon.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

SIZES=(16 32 48 128 256 512 1024)
TIFFS=()

for size in "${SIZES[@]}"; do
    tiff="$WORK/icon-$size.tiff"
    sips -z "$size" "$size" -s format tiff "$SOURCE" --out "$tiff" >/dev/null
    TIFFS+=("$tiff")
done

tiffutil -catnosizecheck "${TIFFS[@]}" -out "$WORK/AppIcon.tiff" >/dev/null
tiff2icns "$WORK/AppIcon.tiff" "$OUTPUT"

print "$OUTPUT"
