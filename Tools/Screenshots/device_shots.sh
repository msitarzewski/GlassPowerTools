#!/bin/bash
# The website's three device pictures, from the simulators (the Mac's come from the VM: site_shots.sh):
# site/static/shots/vision-terminal.webp, ipad-library.webp and iphone-terminal.webp, in Dark Mode.
#
#   IOS_APP=<Debug-iphonesimulator/Glass Power Tools.app> VISION_APP=<Debug-xrsimulator/Glass Power Tools.app> \
#     Tools/Screenshots/device_shots.sh
#
# Build those apps first (the demo mode is DEBUG-only), as capture.sh does. Simulators boot headless; nothing
# opens on this Mac's screen. Look at every picture before publishing it.
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${IOS_APP:?set IOS_APP to a Debug iOS simulator build}"
: "${VISION_APP:?set VISION_APP to a Debug visionOS simulator build}"
RAW=.scratch/shots/sim
OUT=site/static/shots
mkdir -p "$RAW" "$OUT"

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
shot() {  # name app udid surface settle
  APP="$2" Tools/Screenshots/shoot.sh "$3" "$4" "$RAW/$1.png" "$5"
}

IPAD="$(simulator "iPad Pro 13-inch (M5)")"; IPHONE="$(simulator "iPhone 17 Pro Max")"; VISION="$(simulator "Apple Vision Pro")"
for s in "$IPAD" "$IPHONE" "$VISION"; do [ -n "$s" ] || { echo "device_shots: a simulator is missing" >&2; exit 1; }; done
ready "$IPAD" ios; ready "$IPHONE" ios; ready "$VISION"
shot ipad-library "$IOS_APP" "$IPAD" library-history 16
shot iphone-terminal "$IOS_APP" "$IPHONE" terminal 14
shot vision-terminal "$VISION_APP" "$VISION" terminal 25

python3 -I - "$RAW" "$OUT" <<'PY'
import sys
from PIL import Image
raw, out = sys.argv[1], sys.argv[2]
for name, width in [("vision-terminal", 2400), ("ipad-library", 1200), ("iphone-terminal", 780)]:
    im = Image.open(f"{raw}/{name}.png").convert("RGB")
    height = round(im.size[1] * width / im.size[0])
    im.resize((width, height), Image.LANCZOS).save(f"{out}/{name}.webp", "WEBP", quality=86, method=6)
    print(f"{out}/{name}.webp: {width}x{height}")
PY
