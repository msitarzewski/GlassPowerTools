#!/bin/bash
# The website's device pictures, from the simulators (the Mac's come from the VM: site_shots.sh), in Dark Mode:
# site/static/shots/vision-*.webp, ipad-library.webp and iphone-terminal.webp.
#
#   IOS_APP=<Debug-iphonesimulator/Glass Power Tools.app> VISION_APP=<Debug-xrsimulator/Glass Power Tools.app> \
#     Tools/Screenshots/device_shots.sh
#
# Build those apps first (the demo mode is DEBUG-only), as capture.sh does. Simulators boot headless; nothing
# opens on this Mac's screen. On Vision Pro every window is at Opacity 78%, Glass 50%, Medium (the owner's choice,
# 2026-10-18), and the service pictures close the Connections window, so the room shows through the glass. The
# terminals run a btop-style monitor. Look at every picture before publishing it.
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${IOS_APP:?set IOS_APP to a Debug iOS simulator build}"
: "${VISION_APP:?set VISION_APP to a Debug visionOS simulator build}"
RAW=.scratch/shots/sim
OUT=site/static/shots
GLASS="--demo-glass 0.78,0.5,thin"
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
shot() {  # name app udid surface settle [demo arguments]
  APP="$2" DEMO_ARGS="${6:-}" Tools/Screenshots/shoot.sh "$3" "$4" "$RAW/$1.png" "$5"
}

IPAD="$(simulator "iPad Pro 13-inch (M5)")"; IPHONE="$(simulator "iPhone 17 Pro Max")"; VISION="$(simulator "Apple Vision Pro")"
for s in "$IPAD" "$IPHONE" "$VISION"; do [ -n "$s" ] || { echo "device_shots: a simulator is missing" >&2; exit 1; }; done
ready "$IPAD" ios; ready "$IPHONE" ios; ready "$VISION"
shot ipad-library "$IOS_APP" "$IPAD" library-history 16
shot iphone-terminal "$IOS_APP" "$IPHONE" btop 14
shot vision-terminal "$VISION_APP" "$VISION" btop 28 "$GLASS --demo-close-connections"
shot vision-database "$VISION_APP" "$VISION" database 28 "$GLASS --demo-close-connections"
shot vision-desktop "$VISION_APP" "$VISION" desktop 28 "$GLASS --demo-close-connections"
shot vision-editor "$VISION_APP" "$VISION" editor 28 "$GLASS --demo-close-connections"
shot vision-active "$VISION_APP" "$VISION" active 25 "$GLASS"
shot vision-workgroups "$VISION_APP" "$VISION" workgroups 25 "$GLASS"

# The empty room, to find each Vision Pro picture's windows against.
xcrun simctl terminate "$VISION" com.glasspowertools >/dev/null 2>&1 || true
sleep 4
xcrun simctl io "$VISION" screenshot "$RAW/vision-room.png" >/dev/null 2>&1

python3 -I - "$RAW" "$OUT" <<'PY'
import sys
from PIL import Image, ImageChops, ImageFilter
raw, out = sys.argv[1], sys.argv[2]
room = Image.open(f"{raw}/vision-room.png").convert("RGB")
for name in ["vision-terminal", "vision-database", "vision-desktop", "vision-editor", "vision-active", "vision-workgroups"]:
    shot = Image.open(f"{raw}/{name}.png").convert("RGB")
    # Where the windows and their controls are: what differs from the empty room, specks removed.
    diff = ImageChops.difference(shot, room).convert("L").point(lambda v: 255 if v > 28 else 0)
    diff = diff.resize((diff.width // 8, diff.height // 8)).filter(ImageFilter.MinFilter(3))
    left, top, right, bottom = (v * 8 for v in diff.getbbox())
    # A 16:9 frame around them, a third larger, inside the capture: the room around the windows, not all of it.
    width = min(shot.width, max((right - left) * 1.35, (bottom - top) * 1.35 * 16 / 9))
    height = width * 9 / 16
    x = min(max((left + right) / 2 - width / 2, 0), shot.width - width)
    y = min(max((top + bottom) / 2 - height / 2, 0), shot.height - height)
    framed = shot.crop((round(x), round(y), round(x + width), round(y + height)))
    framed.resize((2400, 1350), Image.LANCZOS).save(f"{out}/{name}.webp", "WEBP", quality=86, method=6)
    print(f"{out}/{name}.webp: 2400x1350")
for name, width in [("ipad-library", 1200), ("iphone-terminal", 780)]:
    im = Image.open(f"{raw}/{name}.png").convert("RGB")
    height = round(im.size[1] * width / im.size[0])
    im.resize((width, height), Image.LANCZOS).save(f"{out}/{name}.webp", "WEBP", quality=86, method=6)
    print(f"{out}/{name}.webp: {width}x{height}")
PY
