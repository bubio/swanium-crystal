#!/bin/sh
set -eu

binary=${1:?usage: package_linux_deb.sh BINARY OUTPUT_DEB}
output=${2:?usage: package_linux_deb.sh BINARY OUTPUT_DEB}
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=$(sed -n 's/^version: *//p' "$root/shard.yml" | head -n 1)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
install -D -m 755 "$binary" "$stage/usr/bin/swanium-crystal"
install -D -m 644 "$root/assets/macos/AppIcon.png" "$stage/usr/share/icons/hicolor/1024x1024/apps/swanium-crystal.png"
install -D -m 644 "$root/tools/linux/swanium-crystal.desktop" "$stage/usr/share/applications/swanium-crystal.desktop"
mkdir -p "$stage/DEBIAN" "$(dirname "$output")"
cat > "$stage/DEBIAN/control" <<EOF
Package: swanium-crystal
Version: $version
Section: games
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libsdl2-2.0-0, libssl3 | libssl1.1
Maintainer: Swanium Crystal contributors
Description: WonderSwan emulator
EOF
dpkg-deb --build --root-owner-group "$stage" "$output"
