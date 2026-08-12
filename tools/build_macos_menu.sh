#!/bin/sh
set -eu

output=${1:?usage: build_macos_menu.sh OUTPUT}
mkdir -p "$(dirname "$output")"
clang -fobjc-arc $(pkg-config --cflags sdl2) -c src/swanium/frontend/macos_menu.m -o "$output"
