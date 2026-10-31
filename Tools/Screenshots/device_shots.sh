#!/bin/bash
# The website's device pictures, from the simulators (the Mac's come from the VM: site_shots.sh), in Dark Mode:
# site/static/shots/vision-*.webp, ipad-landscape.webp and iphone-terminal.webp.
#
#   IOS_APP=<Debug-iphonesimulator/Glass Power Tools.app> VISION_APP=<Debug-xrsimulator/Glass Power Tools.app> \
#     IOS_XCTESTRUN=<a Debug iOS Simulator build-for-testing's .xctestrun> Tools/Screenshots/device_shots.sh [name …]
#
# With names (vision-dock, vision-editor-git, …), only those are taken again; the others are left as they are.
#
# Build those apps first (the demo mode is DEBUG-only), as capture.sh does. Simulators boot headless; nothing
# opens on this Mac's screen. On Vision Pro every window is at Opacity 78%, Glass 50%, Medium (the owner's choice,
# 2026-10-18), and the service pictures close the Connections window, so the room shows through the glass. The
# terminals run a btop-style monitor. The iPad's library is in landscape (the owner, 2026-10-30: "Use a landscape
# iPad image to show the same screen, just more full"): iPadOS ignores the app's own request to turn, so a UI test
# (UITests/SiteShotsUITests.swift) turns the simulator, takes the picture and turns it back. Look at every picture
# before publishing it.
set -euo pipefail
cd "$(dirname "$0")/../.."
ONLY=" $* "
RAW=.scratch/shots/sim
OUT=site/static/shots
GLASS="--demo-glass 0.78,0.5,thin"
. Tools/Screenshots/demo-hosts.sh
mkdir -p "$RAW" "$OUT"

simulator() {  # the available simulator named exactly this, on the newest runtime that has one: the list runs
  # oldest first, and an older runtime kept for the oldest supported release (26.5) must not stand in (2026-10-31)
  xcrun simctl list devices available | awk -v prefix="    $1 (" '
    index($0, prefix) == 1 { rest = substr($0, length(prefix) + 1)
      if (substr(rest, 37, 1) == ")" && substr(rest, 1, 36) !~ /[^0-9A-F-]/) id = substr(rest, 1, 36) }
    END { print id }'
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
shot() {  # name app udid surface settle [demo arguments] [an orb's name to show]
  [ -z "${ONLY// /}" ] || [[ "$ONLY" == *" $1 "* ]] || return 0
  [ -n "$2" ] || { echo "device_shots: $1 needs IOS_APP or VISION_APP, a Debug simulator build" >&2; exit 1; }
  APP="$2" DEMO_ARGS="${6:-}" DEMO_ORB_NAME="${7:-}" DEMO_ENVIRONMENTS="${DEMO_ENVIRONMENTS:-}" \
    Tools/Screenshots/shoot.sh "$3" "$4" "$RAW/$1.png" "$5"
}

IPAD="$(simulator "iPad Pro 13-inch (M5)")"; IPHONE="$(simulator "iPhone 17 Pro Max")"; VISION="$(simulator "Apple Vision Pro")"
for s in "$IPAD" "$IPHONE" "$VISION"; do [ -n "$s" ] || { echo "device_shots: a simulator is missing" >&2; exit 1; }; done
# Only the simulators the pictures asked for are started.
if [ -z "${ONLY// /}" ] || [[ "$ONLY" == *" ipad-"* ]]; then ready "$IPAD" ios; fi
if [ -z "${ONLY// /}" ] || [[ "$ONLY" == *" iphone-"* ]]; then ready "$IPHONE" ios; fi
ready "$VISION"
# A new name for the new shape: browsers keep the site's pictures a week, and an old portrait one under the old name
# would be squeezed into the landscape frame.
if [ -z "${ONLY// /}" ] || [[ "$ONLY" == *" ipad-landscape "* ]]; then
  [ -n "${IOS_XCTESTRUN:-}" ] || { echo "device_shots: ipad-landscape needs IOS_XCTESTRUN" >&2; exit 1; }
  TEST_RUNNER_GPT_SHOTS_DIR="$PWD/$RAW" TEST_RUNNER_GPT_DEMO_HOSTS="$HOSTS" xcodebuild test-without-building \
    -xctestrun "$IOS_XCTESTRUN" -destination "id=$IPAD" \
    -only-testing:GlassPowerToolsUITests/SiteShotsUITests/testIPadLibraryInLandscape -quiet
fi
shot iphone-terminal "${IOS_APP:-}" "$IPHONE" btop 14
shot vision-terminal "${VISION_APP:-}" "$VISION" btop 28 "$GLASS --demo-close-connections"
shot vision-database "${VISION_APP:-}" "$VISION" database 28 "$GLASS --demo-close-connections"
shot vision-desktop "${VISION_APP:-}" "$VISION" desktop 28 "$GLASS --demo-close-connections"
shot vision-editor "${VISION_APP:-}" "$VISION" editor 28 "$GLASS --demo-close-connections"
shot vision-active "${VISION_APP:-}" "$VISION" active 25 "$GLASS"
shot vision-workgroups "${VISION_APP:-}" "$VISION" workgroups 25 "$GLASS"
# 2026-10-30: Git in the editor (a taller window, so Changes shows more than its first file), and the orb dock
# (D88) by itself, then closer, one tab's name showing as a look shows it.
shot vision-editor-git "${VISION_APP:-}" "$VISION" editor-git 32 "$GLASS --demo-close-connections --demo-editor-size 1150,1050"
# The dock as the owner keeps his (2026-10-31: "the terminal above with tabs open and the full dock below"): the
# dock opens under a short Connections window, low enough for the simulator's fixed view, and a terminal with its
# tabs comes back above it. The close-up keeps the dock alone: in this layout a dot's name is drawn under the
# terminal's toolbar.
shot vision-dock "${VISION_APP:-}" "$VISION" dock 45 "$GLASS --demo-close-connections --demo-dock-below --demo-library-size 1000x200"
shot vision-dock-name "${VISION_APP:-}" "$VISION" dock 40 "$GLASS --demo-close-connections --demo-dock-alone" \
  "✳ Storefront checkout redesign"
# Focus Mode in rooms of one's own (D89; the owner, 2026-10-30, "screen shots for the site"): the loft, Midtown out of
# its windows, its sounds and events beside it; and the ridge studio, glass walls over a meadow. The rooms are the
# owner's (made in the GlassSpaceMaker session), not in this repository: ENVIRONMENTS_DIR is the folder that holds
# them, and without it these two are skipped. Each is seen from a step of Fine Position's (`--demo-nudge`): the loft
# 1.2 m nearer its windows, so its digital clock stands above the terminal ("should have a digital clock above the
# window"), past a desk no pinch can reach over; the studio turned 70° to the right, toward its glass and the hills.
if [ -n "${ENVIRONMENTS_DIR:-}" ]; then
  DEMO_ENVIRONMENTS="$ENVIRONMENTS_DIR/Loft.usdz:$ENVIRONMENTS_DIR/Loft.sounds:$ENVIRONMENTS_DIR/Loft.events" \
    shot vision-focus-loft "${VISION_APP:-}" "$VISION" btop 45 \
    "$GLASS --demo-close-connections --demo-focus file:Loft.usdz --demo-focus-immersed --demo-nudge 1.2,0,0"
  DEMO_ENVIRONMENTS="$ENVIRONMENTS_DIR/RidgeStudio.usdz" \
    shot vision-focus-ridge "${VISION_APP:-}" "$VISION" btop 45 \
    "$GLASS --demo-close-connections --demo-focus file:RidgeStudio.usdz --demo-focus-immersed --demo-nudge 0,0,-70"
fi

# The empty room, to find each Vision Pro picture's windows against.
xcrun simctl terminate "$VISION" com.glasspowertools >/dev/null 2>&1 || true
sleep 4
xcrun simctl io "$VISION" screenshot "$RAW/vision-room.png" >/dev/null 2>&1

python3 -I - "$RAW" "$OUT" $ONLY <<'PY'
import os
import sys
from PIL import Image, ImageChops, ImageFilter
raw, out, only = sys.argv[1], sys.argv[2], set(sys.argv[3:])
room = Image.open(f"{raw}/vision-room.png").convert("RGB")
# A close-up: the share of what was found to frame, from its left edge, and the room around it.
closer = {"vision-dock-name": (0.62, 1.12)}
for name in ["vision-terminal", "vision-database", "vision-desktop", "vision-editor", "vision-active", "vision-workgroups",
             "vision-editor-git", "vision-dock", "vision-dock-name"]:
    if only and name not in only:
        continue
    shot = Image.open(f"{raw}/{name}.png").convert("RGB")
    # Where the windows and their controls are: what differs from the empty room, specks removed.
    diff = ImageChops.difference(shot, room).convert("L").point(lambda v: 255 if v > 28 else 0)
    diff = diff.resize((diff.width // 8, diff.height // 8)).filter(ImageFilter.MinFilter(3))
    if name in closer:
        # The dock is high in the room, and the room below it changes a little from run to run: found in the
        # upper half alone, then framed from its left edge, the given share of it wide.
        share, pad = closer[name]
        left, top, right, bottom = (v * 8 for v in diff.crop((0, 0, diff.width, diff.height // 2)).getbbox())
        width = (right - left) * share
        height = width * 9 / 16
        x = max(left - width * (pad - 1) / 2, 0)
        y = max(top - height * (pad - 1), 0)
    else:
        left, top, right, bottom = (v * 8 for v in diff.getbbox())
        # A 16:9 frame around them, a third larger, inside the capture: the room around the windows, not all of it.
        width = min(shot.width, max((right - left) * 1.35, (bottom - top) * 1.35 * 16 / 9))
        height = width * 9 / 16
        x = min(max((left + right) / 2 - width / 2, 0), shot.width - width)
        y = min(max((top + bottom) / 2 - height / 2, 0), shot.height - height)
    framed = shot.crop((round(x), round(y), round(x + width), round(y + height)))
    framed.resize((2400, 1350), Image.LANCZOS).save(f"{out}/{name}.webp", "WEBP", quality=86, method=6)
    print(f"{out}/{name}.webp: 2400x1350")
# Focus Mode's room fills the view: the whole capture, 16:9 from its middle.
for name in ["vision-focus-loft", "vision-focus-ridge"]:
    if (only and name not in only) or not os.path.exists(f"{raw}/{name}.png"):
        continue
    shot = Image.open(f"{raw}/{name}.png").convert("RGB")
    width, height = shot.width, round(shot.width * 9 / 16)
    if height > shot.height:
        width, height = round(shot.height * 16 / 9), shot.height
    x, y = (shot.width - width) // 2, (shot.height - height) // 2
    shot.crop((x, y, x + width, y + height)).resize((2400, 1350), Image.LANCZOS).save(f"{out}/{name}.webp", "WEBP", quality=86, method=6)
    print(f"{out}/{name}.webp: 2400x1350")
for name, width in [("ipad-landscape", 1600), ("iphone-terminal", 780)]:
    if only and name not in only:
        continue
    im = Image.open(f"{raw}/{name}.png").convert("RGB")
    # The UI test's capture is the iPad's screen as it is fixed, portrait, with the landscape picture across it.
    if name == "ipad-landscape" and im.height > im.width:
        im = im.rotate(90, expand=True)
    height = round(im.size[1] * width / im.size[0])
    im.resize((width, height), Image.LANCZOS).save(f"{out}/{name}.webp", "WEBP", quality=86, method=6)
    print(f"{out}/{name}.webp: {width}x{height}")
PY
