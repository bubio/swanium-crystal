#!/bin/sh
# Build the macOS .icns bundle resource from the committed 1024px source PNG.
set -eu

source=${1:?usage: build_macos_icon.sh SOURCE_PNG OUTPUT_ICNS}
output=${2:?usage: build_macos_icon.sh SOURCE_PNG OUTPUT_ICNS}
iconset=$(mktemp -d "${TMPDIR:-/tmp}/swanium-crystal-icon.XXXXXX.iconset")

cleanup() {
  rm -rf "$iconset"
}
trap cleanup EXIT HUP INT TERM

test -f "$source"
mkdir -p "$(dirname "$output")"

resize() {
  pixels=$1
  name=$2
  sips --resampleHeightWidth "$pixels" "$pixels" "$source" --out "$iconset/$name" >/dev/null
}

resize 16 icon_16x16.png
resize 32 icon_16x16@2x.png
resize 32 icon_32x32.png
resize 64 icon_32x32@2x.png
resize 128 icon_128x128.png
resize 256 icon_128x128@2x.png
resize 256 icon_256x256.png
resize 512 icon_256x256@2x.png
resize 512 icon_512x512.png
resize 1024 icon_512x512@2x.png

rm -f "$output"
iconutil --convert icns --output "$output" "$iconset"
