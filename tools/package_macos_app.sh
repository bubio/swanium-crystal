#!/bin/sh
# Archive a completed app bundle for GitHub Actions artifacts or releases.
set -eu

app=${1:?usage: package_macos_app.sh APP_BUNDLE OUTPUT_ZIP}
archive=${2:?usage: package_macos_app.sh APP_BUNDLE OUTPUT_ZIP}

test -d "$app"
mkdir -p "$(dirname "$archive")"
rm -f "$archive"
ditto -c -k --keepParent "$app" "$archive"
