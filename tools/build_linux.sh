#!/bin/sh
# Build the native Linux executable. GTK3 and SDL2 stay system dependencies
# for distro packages.
set -eu

output=${1:-bin/swanium-crystal}
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$(dirname "$output")"
object="$root/bin/linux_menu.o"
mkdir -p "$(dirname "$object")"
cc $(pkg-config --cflags gtk+-3.0 gdk-x11-3.0 sdl2) -c "$root/src/swanium/frontend/linux_menu.c" -o "$object"
exec crystal build --release --no-debug --link-flags "$object $(pkg-config --libs gtk+-3.0 gdk-x11-3.0)" "$root/src/swanium.cr" -o "$output"
