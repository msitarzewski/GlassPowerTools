#!/bin/bash
# Screenshots of every surface on the simulators, from the real app on made-up data (App/GlassDemoMode.swift).
# The website's own pictures come from site_shots.sh (the Mac, in the VM) and device_shots.sh.
#   Tools/Screenshots/capture.sh [visionos] [ipad] [iphone]      (default: all three, in that order)
# Builds the Debug app once per platform (the demo code is DEBUG-only), then shoots each surface
# on that platform's simulator into site/static/shots/<platform>-<surface>.png.
# Look at every picture before publishing it: nothing personal belongs in them.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="${OUT:-site/static/shots}"
DD="${DERIVED_DATA:-${TMPDIR:-/tmp}/glass-shots-dd}"
SURFACES="${SURFACES:-library editor preview terminal database diagram desktop}"
mkdir -p "$OUT"

simulator() {  # the available simulator named exactly this, on the newest runtime that has one: the list runs
  # oldest first, and an older runtime kept for the oldest supported release (26.5) must not stand in (2026-10-31)
  xcrun simctl list devices available | awk -v prefix="    $1 (" '
    index($0, prefix) == 1 { rest = substr($0, length(prefix) + 1)
      if (substr(rest, 37, 1) == ")" && substr(rest, 1, 36) !~ /[^0-9A-F-]/) id = substr(rest, 1, 36) }
    END { print id }'
}

for PLATFORM in ${@:-visionos ipad iphone}; do
  case "$PLATFORM" in
    visionos) NAME="Apple Vision Pro"; DEST="visionOS Simulator"; PRODUCTS=Debug-xrsimulator; SETTLE=20 ;;
    ipad) NAME="iPad Pro 13-inch (M5)"; DEST="iOS Simulator"; PRODUCTS=Debug-iphonesimulator; SETTLE=12 ;;
    iphone) NAME="iPhone 17 Pro"; DEST="iOS Simulator"; PRODUCTS=Debug-iphonesimulator; SETTLE=12 ;;
    *) echo "capture: unknown platform $PLATFORM" >&2; exit 2 ;;
  esac
  SIM="$(simulator "$NAME")"
  [ -n "$SIM" ] || { echo "capture: no simulator named $NAME" >&2; exit 1; }
  xcrun simctl boot "$SIM" 2>/dev/null || true
  xcrun simctl bootstatus "$SIM" >/dev/null
  if [ "$PLATFORM" != visionos ]; then
    xcrun simctl status_bar "$SIM" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
      --cellularBars 4 --batteryState charged --batteryLevel 100 >/dev/null
  fi
  echo "capture: building for $NAME"
  xcodebuild -project GlassPowerTools.xcodeproj -scheme GlassPowerTools -configuration Debug \
    -destination "platform=$DEST,id=$SIM" -derivedDataPath "$DD" \
    -packageAuthorizationProvider netrc -skipPackagePluginValidation build -quiet
  APP="$DD/Build/Products/$PRODUCTS/Glass Power Tools.app"
  for SURFACE in $SURFACES; do
    APP="$APP" Tools/Screenshots/shoot.sh "$SIM" "$SURFACE" "$OUT/$PLATFORM-$SURFACE.png" "$SETTLE"
  done
done
