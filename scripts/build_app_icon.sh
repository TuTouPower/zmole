#!/bin/bash
# Regenerate src/zmole/Resources/AppIcon.icns from the vector icon source.
#
# The source lives in assets/ and is the visual authority for the app icon;
# the .icns in src/zmole/Resources/ is a generated artifact that must be
# refreshed with this script whenever the source changes.
#
# The SVG is rasterized through the system SVG support (ImageIO) into a
# transparent 1024px master, then sliced with sips and packed with iconutil.
# Do not use `qlmanage -t`: it renders a white "document preview" page and
# destroys the icon's transparency.
#
# Usage:
#   scripts/build_app_icon.sh [source.svg] [output.icns]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${1:-$REPO_ROOT/assets/app_icon_source.svg}"
OUTPUT="${2:-$REPO_ROOT/src/zmole/Resources/AppIcon.icns}"

for tool in swift sips iconutil; do
    command -v "$tool" > /dev/null 2>&1 || {
        echo "build_app_icon: $tool is required" >&2
        exit 1
    }
done
[[ -f "$SOURCE" ]] || {
    echo "build_app_icon: source not found: $SOURCE" >&2
    exit 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MASTER="$WORK/master.png"
swift "$REPO_ROOT/scripts/svg_to_png.swift" "$SOURCE" "$MASTER" 1024
[[ -f "$MASTER" ]] || {
    echo "build_app_icon: renderer produced no PNG for $SOURCE" >&2
    exit 1
}

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
while read -r size name; do
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_$name.png" > /dev/null
done <<'SIZES'
16 16x16
32 16x16@2x
32 32x32
64 32x32@2x
128 128x128
256 128x128@2x
256 256x256
512 256x256@2x
512 512x512
1024 512x512@2x
SIZES

mkdir -p "$(dirname "$OUTPUT")"
iconutil -c icns "$ICONSET" -o "$OUTPUT"
echo "build_app_icon: wrote $OUTPUT from $SOURCE"
