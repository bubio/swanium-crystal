#!/bin/sh
set -eu

binary=${1:-bin/swanium-crystal}
window_class=${2:-swanium-crystal}
title='Swanium Crystal'
helper=${TMPDIR:-/tmp}/swanium-send-wm-delete-$$
state_root=$(mktemp -d "${TMPDIR:-/tmp}/swanium-launcher.XXXXXX")
export XDG_STATE_HOME=$state_root
cc -Wall -Wextra -Werror tools/linux/send_wm_delete.c -lX11 -o "$helper"

pid=
cleanup() {
  [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
  rm -f "$helper"
  rm -rf "$state_root"
}
trap cleanup EXIT INT TERM

run=1
while [ "$run" -le 3 ]; do
  "$binary" &
  pid=$!

  attempt=0
  window=
  while [ "$attempt" -lt 100 ]; do
    for candidate in $(xdotool search --name "^$title$" 2>/dev/null || true); do
      # SDL_CreateWindowFrom gives the embedded X11 child the same title as
      # the GTK window. Only the window-manager client (the GTK top-level)
      # owns the ICCCM WM_STATE property. On bare Xvfb/rootful XWayland there
      # is no WM, so the GTK top-level is instead identified as a root child.
      # Closing the embedded child would bypass the normal delete-event path.
      if xprop -id "$candidate" WM_STATE 2>/dev/null | grep -q 'window state:' ||
         xwininfo -id "$candidate" -tree 2>/dev/null | grep -q 'Parent window id:.*root window'; then
        window=$candidate
        break
      fi
    done
    [ -n "$window" ] && break
    attempt=$((attempt + 1))
    sleep 0.01
  done

  if [ -z "$window" ]; then
    echo "launcher window did not appear on run $run" >&2
    exit 1
  fi

  count=$(xwininfo -root -tree 2>/dev/null | grep -F "\"$title\"" | grep -F -c "(\"$window_class\"" || true)
  if [ "$count" -ne 1 ]; then
    echo "expected one launcher application window, found $count on run $run" >&2
    exit 1
  fi

  "$helper" "$window"
  wait "$pid"
  pid=
  run=$((run + 1))
done
echo "launcher smoke passed 3 times: one GTK top-level and clean WM close"
