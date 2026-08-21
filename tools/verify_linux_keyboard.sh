#!/bin/sh
set -eu

binary=${1:-bin/swanium-crystal}
title='Swanium Crystal SDL2 smoke test'
state_root=$(mktemp -d "${TMPDIR:-/tmp}/swanium-keyboard.XXXXXX")
export XDG_STATE_HOME=$state_root
pid=
cleanup() {
  [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
  rm -rf "$state_root"
}
trap cleanup EXIT INT TERM

SWANIUM_EXPECT_KEYBOARD_SMOKE=1 "$binary" --sdl-smoke &
pid=$!

attempt=0
window=
while [ "$attempt" -lt 100 ]; do
  # Background-launched windows can be reported Iconic by the surrounding
  # desktop automation session even though their X11 children are mapped.
  # The renderer-ready title is the reliable synchronization point here.
  window=$(xdotool search --name "^$title$" 2>/dev/null | head -n 1 || true)
  [ -n "$window" ] && break
  attempt=$((attempt + 1))
  sleep 0.01
done

if [ -z "$window" ]; then
  echo "keyboard smoke window did not appear" >&2
  exit 1
fi

sleep 0.2
xdotool windowmap --sync "$window"
xdotool windowfocus --sync "$window"
xdotool mousemove --window "$window" 100 100
xdotool click 1
xdotool key --clearmodifiers a
wait "$pid"
pid=
echo "keyboard smoke passed: X11 key event reached the SDL child wrapper"
