#!/usr/bin/env bash
# Drive the mirrored iPhone through the rPlay mirror window with XTEST.
#
#   ptap.sh tap  <phone_x> <phone_y>
#   ptap.sh swipe <x1> <y1> <x2> <y2> [steps]
#
# Phone coordinates are in the AirPlay stream space (532x1080); they are scaled
# to the mirror window automatically.
set -euo pipefail

PHONE_W=532
PHONE_H=1080

XDOTOOL="${XDOTOOL:-$(command -v xdotool)}"
export DISPLAY="${DISPLAY:-:2}"

win="$("$XDOTOOL" search --name '\(rPlay\)' 2>/dev/null | tail -1)"
[ -n "${win:-}" ] || { echo "no mirror window found on $DISPLAY" >&2; exit 1; }

eval "$("$XDOTOOL" getwindowgeometry --shell "$win")"
sx=$(python3 -c "print($WIDTH/$PHONE_W)")
sy=$(python3 -c "print($HEIGHT/$PHONE_H)")

px() { python3 -c "print(int($1*$sx))"; }
py() { python3 -c "print(int($1*$sy))"; }

case "${1:-}" in
  tap)
    "$XDOTOOL" mousemove --window "$win" "$(px "$2")" "$(py "$3")"
    sleep 0.2
    "$XDOTOOL" click 1
    ;;
  swipe)
    steps="${6:-12}"
    "$XDOTOOL" mousemove --window "$win" "$(px "$2")" "$(py "$3")"
    "$XDOTOOL" mousedown 1
    for i in $(seq 1 "$steps"); do
      fx=$(python3 -c "print(int(($2 + ($4-$2)*$i/$steps)*$sx))")
      fy=$(python3 -c "print(int(($3 + ($5-$3)*$i/$steps)*$sy))")
      "$XDOTOOL" mousemove --window "$win" "$fx" "$fy"
      sleep 0.02
    done
    "$XDOTOOL" mouseup 1
    ;;
  info)
    echo "window=$win geometry=${WIDTH}x${HEIGHT} scale=${sx}x${sy}"
    ;;
  *)
    sed -n '2,8p' "$0"
    exit 1
    ;;
esac
