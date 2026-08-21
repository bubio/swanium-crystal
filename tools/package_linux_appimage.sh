#!/bin/sh
# linuxdeploy bundles GTK/SDL runtime dependencies; set LINUXDEPLOY to its
# downloaded executable (the Linux CI does this automatically).
set -eu

binary=${1:?usage: package_linux_appimage.sh BINARY OUTPUT_APPIMAGE}
output=${2:?usage: package_linux_appimage.sh BINARY OUTPUT_APPIMAGE}
: "${LINUXDEPLOY:?set LINUXDEPLOY to linuxdeploy}"
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
install -D -m 755 "$binary" "$stage/usr/bin/swanium-crystal"
icon="$stage/swanium-crystal.png"
if command -v magick >/dev/null 2>&1; then
  magick "$root/assets/macos/AppIcon.png" -resize 512x512 "$icon"
elif command -v convert >/dev/null 2>&1; then
  convert "$root/assets/macos/AppIcon.png" -resize 512x512 "$icon"
else
  echo "ImageMagick is required to create the 512x512 AppImage icon" >&2
  exit 1
fi
install -D -m 644 "$icon" "$stage/usr/share/icons/hicolor/512x512/apps/swanium-crystal.png"
install -D -m 644 "$root/tools/linux/swanium-crystal.desktop" "$stage/usr/share/applications/swanium-crystal.desktop"
mkdir -p "$(dirname "$output")"
OUTPUT="$output" "$LINUXDEPLOY" --appdir "$stage" --desktop-file "$root/tools/linux/swanium-crystal.desktop" --icon-file "$icon" --output appimage
