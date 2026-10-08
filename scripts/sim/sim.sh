#!/bin/bash
# sim.sh — drive the booted iOS Simulator from the command line, for UI checks
# (simctl can screenshot and launch, but not tap or swipe).
#
#   sim.sh shot <file.png> [delay]   screenshot at 2× points (wait `delay` s first, default 1)
#   sim.sh tap X Y                   tap at pixel X,Y of a `shot` image
#   sim.sh drag X1 Y1 X2 Y2          drag, same coordinates (spin a hero, scroll a list)
#   sim.sh scroll [N]                N swipes up (content moves up), default 1
#
# Coordinates are pixels of the image `shot` writes, so read a position off a
# screenshot and tap it. Taps are real mouse events on the Simulator window,
# found wherever it is on screen; the window must be visible and at 100% zoom
# (Window ▸ Point Accurate) with device bezels on — the script checks the
# geometry and stops rather than tapping the wrong place. The first tap asks
# for Accessibility permission for the terminal app.
#
# Needs Xcode (DEVELOPER_DIR is exported here, see CLAUDE.md). A dialog over
# the Simulator (e.g. "SimulatorTrampoline wants the Microphone") eats clicks.
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="${XDG_CACHE_HOME:-$HOME/.cache}/marque-sim/simevent"
die() { echo "sim.sh: $*" >&2; exit 1; }

# Build the event helper once (and again when its source changes).
if [ ! -x "$BIN" ] || [ "$HERE/simevent.swift" -nt "$BIN" ]; then
  mkdir -p "$(dirname "$BIN")"
  xcrun swiftc -O "$HERE/simevent.swift" -o "$BIN" || die "could not build simevent"
fi

device() {
  xcrun simctl list devices booted | grep -oE '\([0-9A-F-]{36}\) \(Booted\)' | head -1 | grep -oE '[0-9A-F-]{36}' \
    || die "no booted Simulator"
}

# Device bezel around the screen in the Simulator window at 100% zoom
# (iPhone 17; measured 2026-10-08: window 456×972 pt, screen 402×874 pt at
# +27,+80). Recalibrate with `sim.sh window` against a screenshot if a
# different device or Xcode moves the screen.
BEZEL_X=27; BEZEL_TOP=80

# Screen point of a `shot` pixel: the window's origin + bezel + pixel/2.
to_screen() {
  read -r WX WY WW WH < <("$BIN" window)
  local sw=$((WW - 2 * BEZEL_X))
  # A point-accurate iPhone screen is 375–440 pt wide; anything else means
  # another zoom or bezel setting, and every tap would land wrong.
  [ "$sw" -ge 360 ] && [ "$sw" -le 450 ] || die "Simulator window is ${WW}×${WH} pt — set Window ▸ Point Accurate with bezels on (or recalibrate BEZEL_X/BEZEL_TOP)"
  echo "$1 $2" | awk -v x="$WX" -v y="$WY" -v bx=$BEZEL_X -v bt=$BEZEL_TOP '{ printf "%d %d\n", x + bx + $1 / 2, y + bt + $2 / 2 }'
}

activate() { osascript -e 'tell application "Simulator" to activate' >/dev/null; sleep 0.4; }

case "${1:-}" in
shot)
  [ -n "${2:-}" ] || die "usage: sim.sh shot <file.png> [delay]"
  sleep "${3:-1}"
  xcrun simctl io "$(device)" screenshot "$2" >/dev/null 2>&1 || die "screenshot failed"
  # Native pixels are 3× points on current iPhones; 2× keeps text legible
  # and makes the tap arithmetic exact.
  W=$(sips -g pixelWidth "$2" | awk '/pixelWidth/ { print $2 }')
  sips --resampleWidth $((W * 2 / 3)) "$2" >/dev/null
  echo "$2"
  ;;
tap)
  [ $# -eq 3 ] || die "usage: sim.sh tap X Y"
  activate; read -r SX SY < <(to_screen "$2" "$3"); "$BIN" click "$SX" "$SY"
  ;;
drag)
  [ $# -eq 5 ] || die "usage: sim.sh drag X1 Y1 X2 Y2"
  activate; read -r AX AY < <(to_screen "$2" "$3"); read -r BX BY < <(to_screen "$4" "$5")
  "$BIN" drag "$AX" "$AY" "$BX" "$BY"
  ;;
scroll)
  activate
  read -r AX AY < <(to_screen 400 1100); read -r BX BY < <(to_screen 400 400)
  for _ in $(seq "${2:-1}"); do "$BIN" drag "$AX" "$AY" "$BX" "$BY"; sleep 0.5; done
  ;;
window)
  "$BIN" window
  ;;
*) die "usage: sim.sh shot <file> [delay] | tap X Y | drag X1 Y1 X2 Y2 | scroll [N] | window" ;;
esac
