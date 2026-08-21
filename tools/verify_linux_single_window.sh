#!/bin/sh
set -eu

binary=${1:-bin/swanium-crystal}
window_class=${2:-swanium-crystal}
title='Swanium Crystal SDL2 smoke test'
state_root=$(mktemp -d "${TMPDIR:-/tmp}/swanium-single-window.XXXXXX")
pid=
cleanup() {
  [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
  rm -rf "$state_root"
}
trap cleanup EXIT INT TERM

run=1
while [ "$run" -le 3 ]; do
  XDG_STATE_HOME="$state_root/run-$run" "$binary" --sdl-smoke &
  pid=$!

  attempt=0
  count=0
  # The public title is installed only after SDL_CreateRenderer succeeds, so
  # seeing it also proves the embedded renderer is ready. Allow slower CI
  # software-renderer startup without racing the short smoke run.
  while [ "$attempt" -lt 500 ]; do
    count=$(xwininfo -root -tree 2>/dev/null | grep -F "\"$title\"" | grep -F -c "(\"$window_class\"" || true)
    [ "$count" -gt 0 ] && break
    attempt=$((attempt + 1))
    sleep 0.01
  done

  if [ "$count" -ne 1 ]; then
    echo "expected one '$title' application window, found $count on run $run" >&2
    xwininfo -root -tree 2>/dev/null | grep -F "$title" >&2 || true
    exit 1
  fi

  wait "$pid"
  pid=
  run=$((run + 1))
done
echo "single-window smoke test passed 3 times: one GTK top-level with an SDL2 child wrapper"
