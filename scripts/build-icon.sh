#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VECTOR_SOURCE="$ROOT/Resources/AppIcon.svg"
SOURCE="$ROOT/Resources/AppIcon.png"
OUTPUT="$ROOT/Resources/AppIcon.icns"
WORK="$(mktemp -d /tmp/llorcs-icon.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

render_png() {
    local pixels="$1"
    local render_dir="$WORK/render-$pixels"
    local rendered="$render_dir/AppIcon.svg.png"

    if [[ ! -f "$rendered" ]]; then
        mkdir -p "$render_dir"
        qlmanage -t -s "$pixels" -o "$render_dir" "$VECTOR_SOURCE" >/dev/null 2>&1
    fi

    print "$rendered"
}

flatten_png() {
    local pixels="$1"
    local flattened="$WORK/flat-$pixels.png"

    if [[ ! -f "$flattened" ]]; then
        local jpeg="$WORK/flat-$pixels.jpg"
        sips -s format jpeg -s formatOptions 100 "$(render_png "$pixels")" --out "$jpeg" >/dev/null
        sips -s format png "$jpeg" --out "$flattened" >/dev/null
    fi

    print "$flattened"
}

render_icon() {
    local pixels="$1"
    local filename="$2"
    cp "$(flatten_png "$pixels")" "$ICONSET/$filename"
}

render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

cp "$(flatten_png 1024)" "$SOURCE"
iconutil -c icns "$ICONSET" -o "$OUTPUT"

print "$OUTPUT"
