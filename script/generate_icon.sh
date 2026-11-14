#!/usr/bin/env bash
set -euo pipefail

# Builds AppIcon.png / AppIcon.iconset / AppIcon.icns from the full-bleed artwork.
# Only needed after Resources/AppIcon-artwork.png changes. Uses only Xcode command line tools.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES="$ROOT_DIR/Resources"
ICONSET="$RESOURCES/AppIcon.iconset"
MASTER="$RESOURCES/AppIcon.png"

swift "$ROOT_DIR/script/compose_icon.swift" "$RESOURCES/AppIcon-artwork.png" "$MASTER"

mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  /usr/bin/sips -z "$((size * 2))" "$((size * 2))" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil --convert icns "$ICONSET" --output "$RESOURCES/AppIcon.icns"
printf '%s\n' 'Generated PixelFit AppIcon.png, AppIcon.iconset and AppIcon.icns.'
