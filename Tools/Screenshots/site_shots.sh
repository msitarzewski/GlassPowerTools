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
# picture in the site's colours (macvm/wallpaper.py). Every window is at Opacity 78%, Glass 50%, Medium (the
# owner's choice, 2026-10-18), and the service shots close the Connections window. The picture is that part of
# the screen, cut out by the windows' own outlines: the glass shows what is behind it, as it does on a Mac, and
# the rounded corners are transparent. `workspace` is four windows at once: a terminal running a btop-style
# monitor, a database, a desktop and the editor. Look at every picture before publishing it: nothing personal
# belongs in them.
set -euo pipefail
ROOT=${0:A:h:h:h}
cd "$ROOT"
VM=Tools/Screenshots/macvm/macvm.sh
APP="Glass Power Tools"
RAW="$ROOT/.scratch/shots/macvm"
OUT="$ROOT/site/static/shots"
HOSTS="alpha@192.0.2.10:ssh+database|bravo@192.0.2.20:ssh+rdp|nas@192.0.2.30:ssh|build@192.0.2.40:ssh|win@192.0.2.50:rdp"
GLASS="--demo-glass 0.78,0.5,thin"
mkdir -p "$RAW" "$OUT"

gui() { timeout 90 $VM gui "$1"; }
events() { gui "osascript -e 'tell application \"System Events\" to $1'" >/dev/null 2>&1 || true; }
# The screen-recording notice macOS shows a capture from SSH, pressed away if it's up; and any other banner (macOS
# posts "See what's new in macOS Tahoe"), closed, so none stands over a picture.
notice() {
  timeout 60 $VM tool press UserNotificationCenter Allow >/dev/null 2>&1 || true
  gui "osascript '/Volumes/My Shared Files/macvm/close-banners.applescript'" >/dev/null 2>&1 || true
}

# The screen at 1920 × 1200 points (2x), and the two desktop pictures in the VM. No desktop widgets (glass shows
# them), and no crash report left from an earlier run (it showed through the glass once, 2026-10-18).
prepare() {
  timeout 90 $VM tool display set 1920x1200 >/dev/null
  gui "defaults write com.apple.WindowManager StandardHideWidgets -bool true; killall NotificationCenter" >/dev/null 2>&1 || true
  timeout 60 $VM tool press "Problem Reporter" OK >/dev/null 2>&1 || true
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
launch() {  # surface [more arguments]
  local surface=$1; shift
  timeout 60 $VM quit-app >/dev/null 2>&1 || true
  gui "open -n -a '/Applications/$APP.app' --args --ui-testing $(uuidgen) --ui-testing-seed-hosts '$HOSTS' --demo-open $surface $GLASS $*"
  sleep ${SETTLE:-14}
}
# id and frame ("x,y WxH", points) of the app's normal window titled $1, the newest if several are.
window() { timeout 90 $VM tool windows "$APP" | awk -F'\t' -v t="$1" '$4 == "layer=0" && $6 == t { line = $1 "\t" $5 } END { print line }'; }
alone() {  # title: that window in front, the app's others out of the way
  local title=$1
  [[ $title == "All Connections" ]] || events "tell process \"$APP\" to set value of attribute \"AXMinimized\" of window \"All Connections\" to true"
  raise "$title"
}
raise() {  # title: that window in front
  events "tell process \"$APP\" to set frontmost to true"
  events "tell process \"$APP\" to perform action \"AXRaise\" of window \"$1\""
  sleep 1
}
place() {  # w h: the front window's size, centred on the screen below the menu bar
  local w=$1 h=$2
  timeout 90 $VM tool place "$APP" $(( (1920 - w) / 2 )) $(( 40 + (1150 - h) / 2 )) $w $h >/dev/null
  sleep 2
}
capture() {  # name title…: the screen around those windows, cut out by their outlines
  local name=$1 found id frame x y w h left=100000 top=100000 right=0 bottom=0 i
  shift
  local -a ids frames masks
  for title in "$@"; do
    found="$(window "$title")"
    [[ -n $found ]] || { echo "site_shots: no window titled \"$title\" for $name"; timeout 90 $VM tool windows "$APP"; exit 1; }
    id=${found%%$'\t'*}; frame=${found#*$'\t'}
    x=${frame%%,*}; y=${${frame#*,}%% *}; w=${${frame##* }%x*}; h=${frame##*x}
    (( x < left )) && left=$x; (( y < top )) && top=$y
    (( x + w > right )) && right=$(( x + w )); (( y + h > bottom )) && bottom=$(( y + h ))
    ids+=($id); frames+=("$x $y")
  done
  local commands=""
  for i in {1..${#ids}}; do commands+="screencapture -x -o -t png -l ${ids[$i]} /tmp/shot-mask-$i.png; "; done
  notice
  gui "$commands screencapture -x -t png -R $left,$top,$(( right - left )),$(( bottom - top )) /tmp/shot-region.png"
  sleep 1; notice
  for i in {1..${#ids}}; do
    timeout 60 $VM ssh "cat /tmp/shot-mask-$i.png" > "$RAW/$name-mask-$i.png"
    masks+=("$RAW/$name-mask-$i.png" "${frames[$i]}")
  done
  timeout 60 $VM ssh "cat /tmp/shot-region.png && rm -f /tmp/shot-mask-*.png /tmp/shot-region.png" > "$RAW/$name.png"
  # Each window's outline from its own capture (opaque inside, its corners' edges smooth), placed where the window
  # stands, over the screen.
  python3 -I - "$RAW/$name.png" "$OUT/mac-$name.webp" $(( right - left )) "$left $top" "${masks[@]}" <<'EOF'
import sys
from PIL import Image, ImageChops
region = Image.open(sys.argv[1]).convert("RGBA")
scale = region.size[0] / int(sys.argv[3])
left, top = (int(v) for v in sys.argv[4].split())
alpha = Image.new("L", region.size, 0)
for mask_path, origin in zip(sys.argv[5::2], sys.argv[6::2]):
    x, y = (int(v) for v in origin.split())
    mask = Image.open(mask_path).convert("RGBA").getchannel("A").point(lambda a: min(255, a * 3))
    layer = Image.new("L", region.size, 0)
    layer.paste(mask, (round((x - left) * scale), round((y - top) * scale)))
    alpha = ImageChops.lighter(alpha, layer)
region.putalpha(alpha)
if region.size[0] > 2880:
    region = region.resize((2880, round(region.size[1] * 2880 / region.size[0])), Image.LANCZOS)
region.save(sys.argv[2], "WEBP", quality=88, method=6)
print(f"{sys.argv[2]}: {region.size[0]}x{region.size[1]}")
EOF
}

# shot → surface, its window's title, its size in points, and anything to do before the picture. The service
# shots close the Connections window (`--demo-close-connections`); the library, Active and Workgroups are in it.
typeset -A SURFACE TITLE SIZE BEFORE
SURFACE=(library library-history  terminal btop  database database  diagram diagram  desktop desktop  editor editor
         active active  workgroups workgroups)
TITLE=(library "All Connections"  terminal "alpha"  database "orders"  diagram "main"  desktop "bravo"
       editor "ShippingAddress.swift"  active "Active"  workgroups "Workgroups")
SIZE=(library "1440 900"  terminal "1240 780"  database "1240 780"  diagram "1240 780"  desktop "1240 780"
      editor "1240 780"  active "1440 900"  workgroups "1440 900")
# The demo's desktop has no remote machine behind it, so the Caps Lock state it sends as its window becomes key is
# refused, and the window says the session isn't ready (as it should for a real one): dismissed before the picture.
BEFORE=(terminal "show-sidebar"  desktop "dismiss")
# `workspace`: its four windows by title, and each one's frame (x y w h, points): tiles on the 1920 × 1200 screen,
# with the Dock hidden meanwhile (it draws over windows). 570 points high: the editor's least. The desktop keeps
# its remote screen's shape, so it is narrower, to stay that high.
WORKSPACE_TITLES=("alpha" "orders" "bravo" "ShippingAddress.swift")
WORKSPACE_FRAMES=("24 38 924 570" "972 38 924 570" "56 620 860 570" "972 620 924 570")
dock() {  # hide | show
  timeout 60 $VM ssh "defaults write com.apple.dock autohide -bool $([[ $1 == hide ]] && echo true || echo false); killall Dock" >/dev/null 2>&1 || true
  sleep 3
}

names=("$@")
# `workgroups` and `workspace` are there to name, not in the default set: the Mac's workgroup detail cuts its
# table off at this size, so the site shows the Vision Pro one; and the four windows at once repeated the home
# page's four service pictures, so the owner kept those (2026-10-18).
(( $# )) || names=(library terminal database diagram desktop editor active)
prepare
[[ -n ${(M)names:#database} || -n ${(M)names:#diagram} || -n ${(M)names:#workspace} ]] && shop
for name in $names; do
  [[ -n ${SURFACE[$name]:-} || $name == workspace ]] || { echo "unknown shot: $name"; exit 2; }
  for look in dark light; do
    appearance $look
    if [[ $name == workspace ]]; then
      dock hide
      SETTLE=26 launch workspace --demo-close-connections
      raise "${WORKSPACE_TITLES[1]}"
      for i in {1..${#WORKSPACE_TITLES}}; do
        timeout 90 $VM tool place "$APP" ${=WORKSPACE_FRAMES[$i]} "${WORKSPACE_TITLES[$i]}" >/dev/null
        sleep 1
      done
      timeout 60 $VM tool press "$APP" "Dismiss" >/dev/null 2>&1 || true
      sleep 2
      capture "$name-$look" "${WORKSPACE_TITLES[@]}"
      dock show
      continue
    fi
    case $name in
      library|active|workgroups) launch ${SURFACE[$name]} ;;
      *) launch ${SURFACE[$name]} --demo-close-connections ;;
    esac
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
