#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output=${1:-"$root/bin/linux-native-window-probe"}
mkdir -p "$(dirname "$output")"
cc $(pkg-config --cflags gtk+-3.0 gdk-x11-3.0 sdl2) \
  "$root/tools/linux/native_window_probe.c" \
  $(pkg-config --libs gtk+-3.0 gdk-x11-3.0 sdl2) -o "$output"
exec "$output"
