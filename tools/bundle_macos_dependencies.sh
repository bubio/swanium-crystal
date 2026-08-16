#!/bin/sh
# Copy non-system dylibs into a macOS app bundle and rewrite the executable to
# load them from Contents/Frameworks. This keeps the release bundle independent
# of the SDK prefix used while building it.
set -eu

bundle=${1:?usage: bundle_macos_dependencies.sh APP_BUNDLE}
executable="$bundle/Contents/MacOS/swanium-crystal"
frameworks="$bundle/Contents/Frameworks"

test -f "$executable"
mkdir -p "$frameworks"

copy_library() {
  library=$1
  name=$(basename "$library")
  destination="$frameworks/$name"
  # SDL2 can be discovered from the executable and also supplied explicitly
  # below for SDL2-compat's runtime loading path. Copy it only once: release
  # dylibs commonly preserve a read-only mode, so a second cp cannot replace
  # the first destination reliably.
  test -f "$destination" && return
  cp -L "$library" "$destination"
  install_name_tool -id "@rpath/$name" "$destination"
}

otool -L "$executable" | awk 'NR > 1 { print $1 }' | while IFS= read -r library; do
  case "$library" in
    /System/*|/usr/lib/*) continue ;;
    /*) ;;
    *) continue ;;
  esac

  name=$(basename "$library")
  copy_library "$library"
  # Do not use @rpath here: the compiler can add Homebrew rpaths before ours,
  # which makes Finder launch a different SDL2 (and its SDL3 dependency).
  install_name_tool -change "$library" "@executable_path/../Frameworks/$name" "$executable"
done

# SDL2-compat loads SDL3 at runtime rather than declaring it as a Mach-O
# dependency, so include the fallback name it probes beside libSDL2 as well.
# CI supplies the GitHub-release build explicitly; Homebrew remains the local
# development default.
sdl2=${SWANIUM_SDL2_LIBRARY:-"$(brew --prefix sdl2)/lib/libSDL2-2.0.0.dylib"}
test -f "$sdl2"
copy_library "$sdl2"
install_name_tool -change "@rpath/$(basename "$sdl2")" "@executable_path/../Frameworks/$(basename "$sdl2")" "$executable"

sdl3=${SWANIUM_SDL3_LIBRARY:-"$(brew --prefix sdl3)/lib/libSDL3.0.dylib"}
test -f "$sdl3"
cp -L "$sdl3" "$frameworks/libSDL3.dylib"
install_name_tool -id '@rpath/libSDL3.dylib' "$frameworks/libSDL3.dylib"
