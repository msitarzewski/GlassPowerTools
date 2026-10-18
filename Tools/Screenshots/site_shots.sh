#!/bin/zsh
# The website's Mac screenshots, taken inside the macOS screenshot VM (Tools/Screenshots/macvm), never on this
# Mac's screen, and written to site/static/shots/ as WebP: mac-<shot>-dark.webp and mac-<shot>-light.webp.
#
#   Tools/Screenshots/macvm/macvm.sh build-app        # Debug, ad-hoc signed: the demo mode is DEBUG-only
#   Tools/Screenshots/macvm/macvm.sh start
#   Tools/Screenshots/macvm/macvm.sh install-app
#   Tools/Screenshots/site_shots.sh                   # every shot, or name some: site_shots.sh terminal library
#
# Each shot launches the app fresh on made-up machines (App/GlassDemoMode.swift, as Tools/Screenshots/shoot.sh
# does on the simulators), opens one surface, and gives its window the same frame every time, alone on a desktop
# picture in the site's colours (macvm/wallpaper.py). The picture is that part of the screen, cut out by the
# window's own outline: the glass shows what is behind it, as it does on a Mac, and the rounded corners are
# transparent. Look at every picture before publishing it: nothing personal belongs in them.
set -euo pipefail
ROOT=${0:A:h:h:h}
cd "$ROOT"
VM=Tools/Screenshots/macvm/macvm.sh
APP="Glass Power Tools"
RAW="$ROOT/.scratch/shots/macvm"
OUT="$ROOT/site/static/shots"
HOSTS="alpha@192.0.2.10:ssh+database|bravo@192.0.2.20:ssh+rdp|nas@192.0.2.30:ssh|build@192.0.2.40:ssh|win@192.0.2.50:rdp"
mkdir -p "$RAW" "$OUT"

gui() { timeout 90 $VM gui "$1"; }
events() { gui "osascript -e 'tell application \"System Events\" to $1'" >/dev/null 2>&1 || true; }
# The screen-recording notice macOS shows a capture from SSH, pressed away if it's up.
notice() { timeout 60 $VM tool press UserNotificationCenter Allow >/dev/null 2>&1 || true; }

# The screen at 1920 × 1200 points (2x), and the two desktop pictures in the VM.
prepare() {
  timeout 90 $VM tool display set 1920x1200 >/dev/null
  python3 -I Tools/Screenshots/macvm/wallpaper.py "$RAW" >/dev/null
  for look in dark light; do timeout 60 $VM copy-in "$RAW/wallpaper-$look.png" /Users/admin/Pictures >/dev/null; done
}
appearance() {  # dark | light: the system's appearance and its desktop picture
  events "tell appearance preferences to set dark mode to $([[ $1 == dark ]] && echo true || echo false)"
  timeout 90 $VM tool wallpaper set "/Users/admin/Pictures/wallpaper-$1.png" >/dev/null
  sleep 2
}
# The made-up shop the database surfaces open, in the VM's Documents (a Mac app's documentsDirectory).
shop() {
  python3 -I Tools/Screenshots/make-demo-db.py "$RAW/demo-shop.sqlite" >/dev/null
  timeout 60 $VM copy-in "$RAW/demo-shop.sqlite" /Users/admin/Documents >/dev/null
}
# The app on the made-up machines with one surface open. Each run is a new --ui-testing folder, so nothing carries
# from one shot to the next.
launch() {  # surface
  timeout 60 $VM quit-app >/dev/null 2>&1 || true
  gui "open -n -a '/Applications/$APP.app' --args --ui-testing $(uuidgen) --ui-testing-seed-hosts '$HOSTS' --demo-open $1"
  sleep ${SETTLE:-14}
}
# id and frame ("x,y WxH", points) of the app's normal window titled $1, the newest if several are.
window() { timeout 90 $VM tool windows "$APP" | awk -F'\t' -v t="$1" '$4 == "layer=0" && $6 == t { line = $1 "\t" $5 } END { print line }'; }
alone() {  # title: that window in front, the app's others out of the way
  local title=$1
  [[ $title == "All Connections" ]] || events "tell process \"$APP\" to set value of attribute \"AXMinimized\" of window \"All Connections\" to true"
  events "tell process \"$APP\" to set frontmost to true"
  events "tell process \"$APP\" to perform action \"AXRaise\" of window \"$title\""
  sleep 1
}
place() {  # w h: the front window's size, centred on the screen below the menu bar
  local w=$1 h=$2
  timeout 90 $VM tool place "$APP" $(( (1920 - w) / 2 )) $(( 40 + (1150 - h) / 2 )) $w $h >/dev/null
  sleep 2
}
capture() {  # name title
  local name=$1 found id frame
  found="$(window "$2")"
  [[ -n $found ]] || { echo "site_shots: no window titled \"$2\" for $name"; timeout 90 $VM tool windows "$APP"; exit 1; }
  id=${found%%$'\t'*}; frame=${found#*$'\t'}
  notice
  gui "screencapture -x -o -t png -l $id /tmp/shot-mask.png; screencapture -x -t png -R ${${frame%% *}},${${frame##* }/x/,} /tmp/shot-region.png"
  sleep 1; notice
  timeout 60 $VM ssh "cat /tmp/shot-mask.png" > "$RAW/$name-mask.png"
  timeout 60 $VM ssh "cat /tmp/shot-region.png && rm -f /tmp/shot-mask.png /tmp/shot-region.png" > "$RAW/$name.png"
  # The window's outline from its own capture (opaque inside, its corners' edges smooth), laid over the screen.
  python3 -I - "$RAW/$name.png" "$RAW/$name-mask.png" "$OUT/mac-$name.webp" <<'PY'
import sys
from PIL import Image
region, window = Image.open(sys.argv[1]).convert("RGBA"), Image.open(sys.argv[2]).convert("RGBA")
region = region.resize(window.size)
region.putalpha(window.getchannel("A").point(lambda a: min(255, a * 3)))
region.save(sys.argv[3], "WEBP", quality=88, method=6)
print(f"{sys.argv[3]}: {region.size[0]}x{region.size[1]}")
PY
}

# shot → surface, its window's title, its size in points, and anything to do before the picture.
typeset -A SURFACE TITLE SIZE BEFORE
SURFACE=(library library-history  terminal terminal  database database  diagram diagram  desktop desktop  editor editor)
TITLE=(library "All Connections"  terminal "alpha"  database "orders"  diagram "main"  desktop "bravo"  editor "ShippingAddress.swift")
SIZE=(library "1440 900"  terminal "1240 780"  database "1240 780"  diagram "1240 780"  desktop "1240 780"  editor "1240 780")
# The demo's desktop has no remote machine behind it, so the Caps Lock state it sends as its window becomes key is
# refused, and the window says the session isn't ready (as it should for a real one): dismissed before the picture.
BEFORE=(terminal "show-sidebar"  desktop "dismiss")

names=(${@:-library terminal database diagram desktop editor})
prepare
[[ -n ${(M)names:#database} || -n ${(M)names:#diagram} ]] && shop
for name in $names; do
  [[ -n ${SURFACE[$name]:-} ]] || { echo "unknown shot: $name"; exit 2; }
  for look in dark light; do
    appearance $look
    launch ${SURFACE[$name]}
    alone "${TITLE[$name]}"
    place ${=SIZE[$name]}
    if [[ ${BEFORE[$name]:-} == show-sidebar ]]; then
      timeout 60 $VM tool press "$APP" "Show Sidebar" >/dev/null 2>&1 || true
      sleep 2
      place ${=SIZE[$name]}
    elif [[ ${BEFORE[$name]:-} == dismiss ]]; then
      timeout 60 $VM tool press "$APP" "Dismiss" >/dev/null 2>&1 || true
      sleep 2
    fi
    capture "$name-$look" "${TITLE[$name]}"
  done
done
timeout 60 $VM quit-app >/dev/null 2>&1 || true
appearance light
