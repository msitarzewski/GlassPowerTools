#!/bin/bash
# The App Store's screenshots, from the simulators in Dark Mode, full-frame at the sizes App Store Connect
# takes: build/appstore/screenshots/iphone-6.9 (1320 × 2868, iPhone 17 Pro Max), ipad-13 (2064 × 2752,
# iPad Pro 13-inch (M5)) and vision (3840 × 2160, Apple Vision Pro), each NN-<surface>.png in display order.
#
#   IOS_APP=<Debug-iphonesimulator/Glass Power Tools.app> VISION_APP=<Debug-xrsimulator/Glass Power Tools.app> \
#     Tools/Screenshots/store_shots.sh [iphone] [ipad] [vision]        (default: all three)
#
# Build those apps first (the demo mode is DEBUG-only), as capture.sh does. Simulators boot headless; nothing
# opens on this Mac's screen. The look is the website's (device_shots.sh): Vision Pro windows at Opacity 78%,
# Glass 50%, Medium, Connections closed where one service is shown, terminals running a btop-style monitor,
# made-up machines on 192.0.2.x. Unlike the website's, these are whole screens, not cut-outs: the store shows
# them as they are, without an alpha channel, which App Store Connect refuses. A set is replaced whole, and a
# picture of the wrong size stops the run. Look at every picture before uploading it.
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${IOS_APP:?set IOS_APP to a Debug iOS simulator build}"
: "${VISION_APP:?set VISION_APP to a Debug visionOS simulator build}"
OUT=build/appstore/screenshots
GLASS="--demo-glass 0.78,0.5,thin"
ALONE="$GLASS --demo-close-connections"

# Each set's pictures, in the order the store shows them: surface, seconds to settle, demo arguments. Left
# out, 2026-10-18: the iPhone's library (its first screen is a list of counts, mostly 0, over "Not synced on
# this build", which every --ui-testing run shows), Files (it lists nothing until a machine is connected), the
# iPhone's Workgroups (its first screen asks you to choose one), the iPad's database (upright, its schema
# sidebar lies over the grid and cuts off its left edge) and Vision Pro's workspace (the simulator opens all
# four windows in one place, stacked, the front one cut off at the top). The iPhone's desktop is on its side,
# as a desktop is used: 2868 x 1320, which the store takes for a 6.9-inch iPhone as it takes 1320 x 2868.
IPHONE_SHOTS=(
  "btop|14|"
  "database|14|"
  "desktop|16|--demo-landscape"
  "editor|14|"
  "active|14|"
)
IPAD_SHOTS=(
  "library-history|16|"
  "btop|16|"
  "desktop|16|"
  "editor|16|"
  "workgroups|16|"
  "active|16|"
)
VISION_SHOTS=(
  "btop|28|$ALONE"
  "database|28|$ALONE"
  "desktop|28|$ALONE"
  "editor|28|$ALONE"
  "active|25|$GLASS"
  "workgroups|25|$GLASS"
)

simulator() {  # the first available simulator with this exact name
  xcrun simctl list devices available | grep -F "    $1 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}
ready() {  # udid [ios]
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" >/dev/null
  xcrun simctl ui "$1" appearance dark 2>/dev/null || true
  if [ "${2:-}" = ios ]; then
    xcrun simctl status_bar "$1" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
      --cellularBars 4 --batteryState charged --batteryLevel 100 >/dev/null
  fi
}
take() {  # set app simulator-name width height [ios] -- shot...
  local set="$1" app="$2" name="$3" width="$4" height="$5" kind="$6"; shift 7
  local sim; sim="$(simulator "$name")"
  [ -n "$sim" ] || { echo "store_shots: no simulator named $name" >&2; exit 1; }
  ready "$sim" $kind
  rm -rf "${OUT:?}/$set" && mkdir -p "$OUT/$set"
  local n=0 entry surface settle args file size expected
  for entry in "$@"; do
    IFS='|' read -r surface settle args <<<"$entry"
    n=$((n + 1)); file="$OUT/$set/$(printf %02d $n)-$surface.png"
    APP="$app" DEMO_ARGS="$args" Tools/Screenshots/shoot.sh "$sim" "$surface" "$file" "$settle"
    expected="${width}x$height"
    case "$args" in *--demo-landscape*) expected="${height}x$width" ;; esac
    size="$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w "x" h}')"
    [ "$size" = "$expected" ] || { echo "store_shots: $file is $size, not $expected" >&2; exit 1; }
    # App Store Connect refuses a picture with an alpha channel, and the simulators' captures have one.
    python3 -I -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).convert("RGB").save(sys.argv[1])' "$file"
  done
  xcrun simctl terminate "$sim" com.glasspowertools >/dev/null 2>&1 || true
  # The empty room, which store_frames.py finds each Vision Pro picture's windows against.
  if [ "$set" = vision ]; then
    sleep 4
    xcrun simctl io "$sim" screenshot "$OUT/../vision-room.png" >/dev/null 2>&1
  fi
}

for set in ${@:-iphone ipad vision}; do
  case "$set" in
    iphone) take iphone-6.9 "$IOS_APP" "iPhone 17 Pro Max" 1320 2868 ios -- "${IPHONE_SHOTS[@]}" ;;
    ipad) take ipad-13 "$IOS_APP" "iPad Pro 13-inch (M5)" 2064 2752 ios -- "${IPAD_SHOTS[@]}" ;;
    vision) take vision "$VISION_APP" "Apple Vision Pro" 3840 2160 "" -- "${VISION_SHOTS[@]}" ;;
    *) echo "store_shots: unknown set $set (iphone, ipad or vision)" >&2; exit 2 ;;
  esac
done
echo "store_shots: done; frame them with Tools/Screenshots/store_frames.py, and look at each picture before uploading"
