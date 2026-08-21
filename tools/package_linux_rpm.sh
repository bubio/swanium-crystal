#!/bin/sh
set -eu

binary=${1:?usage: package_linux_rpm.sh BINARY OUTPUT_RPM}
output=${2:?usage: package_linux_rpm.sh BINARY OUTPUT_RPM}
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=$(sed -n 's/^version: *//p' "$root/shard.yml" | head -n 1)
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
mkdir -p "$top/BUILD" "$top/RPMS" "$top/SOURCES" "$top/SPECS" "$top/TMP" "$top/RPMDB"
archive="$top/SOURCES/swanium-crystal-$version.tar.gz"
stage=$(mktemp -d)
mkdir -p "$stage/swanium-crystal-$version"
install -D -m 755 "$binary" "$stage/swanium-crystal-$version/usr/bin/swanium-crystal"
install -D -m 644 "$root/assets/macos/AppIcon.png" "$stage/swanium-crystal-$version/usr/share/icons/hicolor/1024x1024/apps/swanium-crystal.png"
install -D -m 644 "$root/tools/linux/swanium-crystal.desktop" "$stage/swanium-crystal-$version/usr/share/applications/swanium-crystal.desktop"
tar -C "$stage" -czf "$archive" "swanium-crystal-$version"
rm -rf "$stage"
cat > "$top/SPECS/swanium-crystal.spec" <<EOF
Name: swanium-crystal
Version: $version
Release: 1%{?dist}
Summary: WonderSwan emulator
License: MIT
Source0: %{name}-%{version}.tar.gz
Requires: gtk3, SDL2
%description
WonderSwan emulator with native GTK controls.
%prep
%setup -q
%install
cp -a usr %{buildroot}/
%files
/usr/bin/swanium-crystal
/usr/share/applications/swanium-crystal.desktop
/usr/share/icons/hicolor/1024x1024/apps/swanium-crystal.png
EOF
rpmbuild -bb \
  --define "_topdir $top" \
  --define "_tmppath $top/TMP" \
  --define "_dbpath $top/RPMDB" \
  "$top/SPECS/swanium-crystal.spec"
mkdir -p "$(dirname "$output")"
find "$top/RPMS" -name '*.rpm' -exec cp {} "$output" \;
