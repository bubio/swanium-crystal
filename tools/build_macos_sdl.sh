#!/bin/sh
# Build the exact SDL releases used by the macOS CI.  Do not use Homebrew
# bottles here: a bottle built on a newer macOS may not load on our 13.5
# deployment target.
set -eu

prefix=${1:?usage: build_macos_sdl.sh INSTALL_PREFIX}
workdir=${2:-"${prefix}.build"}
sdl3_version=3.4.12
sdl3_sha256=f07b958a9ac5020fb7a44cadb957f658b2149c3c8abb4f63145fac9303249db7
sdl2_compat_version=2.32.70
sdl2_compat_sha256=998fa62557eb46ffe7e5c3e2c123bc332f7df9d9f593b3ceed88ed1158428a44
deployment_target=${MACOSX_DEPLOYMENT_TARGET:-13.5}
architecture=${CMAKE_OSX_ARCHITECTURES:-$(uname -m)}

rm -rf "$prefix" "$workdir"
mkdir -p "$prefix" "$workdir"

fetch() {
  name=$1
  url=$2
  expected_sha256=$3
  archive="$workdir/$name.tar.gz"
  curl --fail --location --retry 3 --show-error --silent "$url" --output "$archive"
  actual_sha256=$(shasum -a 256 "$archive" | awk '{print $1}')
  test "$actual_sha256" = "$expected_sha256" || {
    echo "SHA-256 mismatch for $name" >&2
    exit 1
  }
  tar -xzf "$archive" -C "$workdir"
}

fetch "SDL3-$sdl3_version" \
  "https://github.com/libsdl-org/SDL/releases/download/release-$sdl3_version/SDL3-$sdl3_version.tar.gz" \
  "$sdl3_sha256"

cmake -S "$workdir/SDL3-$sdl3_version" -B "$workdir/sdl3-build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
  -DCMAKE_OSX_ARCHITECTURES="$architecture" \
  -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST_LIBRARY=OFF -DSDL_TESTS=OFF
cmake --build "$workdir/sdl3-build" --parallel 2
cmake --install "$workdir/sdl3-build"

fetch "sdl2-compat-$sdl2_compat_version" \
  "https://github.com/libsdl-org/sdl2-compat/releases/download/release-$sdl2_compat_version/sdl2-compat-$sdl2_compat_version.tar.gz" \
  "$sdl2_compat_sha256"

cmake -S "$workdir/sdl2-compat-$sdl2_compat_version" -B "$workdir/sdl2-compat-build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DCMAKE_INSTALL_RPATH="$prefix/lib" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
  -DCMAKE_OSX_ARCHITECTURES="$architecture" \
  -DCMAKE_PREFIX_PATH="$prefix" \
  -DSDL2COMPAT_TESTS=OFF
cmake --build "$workdir/sdl2-compat-build" --parallel 2
cmake --install "$workdir/sdl2-compat-build"

ln -sf sdl2-compat.pc "$prefix/lib/pkgconfig/sdl2.pc"
test -f "$prefix/lib/libSDL2-2.0.0.dylib"
test -f "$prefix/lib/libSDL3.0.dylib"
