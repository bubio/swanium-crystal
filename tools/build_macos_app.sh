#!/bin/sh
# Assemble an unsigned macOS app bundle from the Crystal executable, the
# AppKit menu object, and the SDL libraries selected by the environment.
set -eu

app=${1:-"bin/Swanium Crystal.app"}
mode=${2:-release}
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
menu_object="$root/bin/macos_menu.o"
executable="$app/Contents/MacOS/swanium-crystal"

case "$mode" in
  release)
    crystal_flags="--release --no-debug"
    ;;
  debug)
    crystal_flags=""
    menu_object="$root/bin/macos_menu-debug.o"
    ;;
  *)
    echo "usage: $0 [APP_BUNDLE] [release|debug]" >&2
    exit 64
    ;;
esac

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$(dirname "$menu_object")"
cp "$root/tools/macos/Info.plist" "$app/Contents/Info.plist"
sh "$root/tools/build_macos_menu.sh" "$menu_object"

# shellcheck disable=SC2086
crystal build $crystal_flags --link-flags "$menu_object -framework Cocoa -framework UniformTypeIdentifiers -Wl,-headerpad_max_install_names" "$root/src/swanium.cr" -o "$executable"
sh "$root/tools/bundle_macos_dependencies.sh" "$app"
codesign --force --deep --sign - "$app"
