#!/bin/bash
# Every screenshot for the website, from the real app on made-up data (App/GlassDemoMode.swift).
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

simulator() {  # the first available simulator with this exact name
  xcrun simctl list devices available | grep -F "    $1 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
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
