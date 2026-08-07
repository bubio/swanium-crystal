#!/bin/sh
# Make a locally built executable find SDL2 from any supported macOS package
# manager, rather than from the Homebrew Cellar used at build time.
set -eu

binary=${1:?usage: relink_macos_sdl.sh BINARY}

sdl_path=$(otool -L "$binary" | awk '/libSDL2[^ ]*\.dylib/ { print $1; exit }')
if [ -z "$sdl_path" ]; then
  echo "SDL2 dependency not found in $binary" >&2
  exit 1
fi

install_name_tool -change "$sdl_path" "@rpath/$(basename "$sdl_path")" "$binary"

# MacPorts, Intel Homebrew, and Apple Silicon Homebrew, respectively.
for library_path in /opt/local/lib /usr/local/lib /opt/homebrew/lib; do
  install_name_tool -add_rpath "$library_path" "$binary"
done
