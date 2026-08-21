#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output=${1:-"$root/bin/linux-native-wayland-probe"}
pkg_config_path=${SDL3_PKG_CONFIG_PATH:-}
if [ -n "$pkg_config_path" ]; then
  export PKG_CONFIG_PATH="$pkg_config_path${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
fi
pkg-config --exists sdl3 gtk+-3.0 gdk-wayland-3.0 || {
  echo "SDL3, GTK3, and GDK Wayland development files are required" >&2
  exit 1
}
mkdir -p "$(dirname "$output")"
cc $(pkg-config --cflags sdl3 gtk+-3.0 gdk-wayland-3.0) \
  "$root/tools/linux/native_wayland_probe.c" \
  $(pkg-config --libs sdl3 gtk+-3.0 gdk-wayland-3.0) -o "$output"
exec "$output"
