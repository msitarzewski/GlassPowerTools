#!/bin/zsh
# The website's Mac screenshots, taken inside the macOS screenshot VM (Tools/Screenshots/macvm), never on this
# Mac's screen, and written to site/static/shots/ as WebP: macbook-<shot>-dark.webp and macbook-<shot>-light.webp,
# the whole screen in Apple's MacBook Pro bezel; mac-look-<name>.webp, a window cut out by its outline.
#
#   Tools/Screenshots/macvm/macvm.sh build-app        # Debug, ad-hoc signed: the demo mode is DEBUG-only
#   Tools/Screenshots/macvm/macvm.sh start
#   Tools/Screenshots/macvm/macvm.sh install-app
#   BEZELS=<Apple's bezel PNGs> Tools/Screenshots/site_shots.sh   # every shot, or name some: … terminal library
#
# The whole-screen pictures are shown in Apple's MacBook Pro (M5) 14-inch bezel (the owner, 2026-10-31), as Apple's
# marketing guidelines ask: Space Black for Dark Mode, Silver for light, placed by bezel.py. The bezels are Apple's
# (Apple Design Resources, Product Bezels), under its licence, and not in this repository: BEZELS is the folder
# holding their PNGs. The screen is that MacBook Pro's own, 1512 × 982 points, and its notch covers the middle of
# the menu bar, as it does on the Mac, so the windows are placed below a notched Mac's taller menu bar.
#
# Each shot launches the app fresh on made-up machines (App/GlassDemoMode.swift, as Tools/Screenshots/shoot.sh
# does on the simulators), opens one surface, and gives its window the same frame every time. Every window is at
# Opacity 78%, Glass 50%, Medium (the owner's choice, 2026-10-18), and the service shots close the Connections
# window. The picture is the whole screen, 1504 × 940 points as a 13-inch MacBook Air's, with the menu bar, the
# clock at 9:41 and macOS's default desktop picture (macvm/wallpaper.py), the owner's choice of 2026-10-30: the
# glass shows a real desktop through it. (Until 2026-10-31 the screen was 1504 × 940, a 13-inch MacBook Air's,
# without a bezel.) The window fills most of the screen, so its text stays readable on the
# site, and is no bigger than what is in it. `looks` are still cut out by the window's outline, for the gallery's
# small pictures. `workspace` is four windows at once: a terminal running a btop-style monitor, a database, a
# desktop and the editor. `editor-git` is the editor's Changes on the made-up shop's repository
# (App/GlassDemoGit.swift, made with the VM's git); `sql` is SQL from a terminal, two windows at once;
# `all-windows` is Show All Windows over a terminal's tabs, a database, a desktop and the editor.
# Look at every picture before publishing it: nothing personal belongs in them.
set -euo pipefail
ROOT=${0:A:h:h:h}
cd "$ROOT"
VM=Tools/Screenshots/macvm/macvm.sh
APP="Glass Power Tools"
RAW="$ROOT/.scratch/shots/macvm"
OUT="$ROOT/site/static/shots"
# Made-up machines in collections (`#`), enough to fill the library as one in use does (2026-10-30).
HOSTS="alpha@192.0.2.10#Production:ssh+database|bravo@192.0.2.20#Office:ssh+rdp|nas@192.0.2.30#Home:ssh"
HOSTS+="|build@192.0.2.40#Production:ssh|win@192.0.2.50#Office:rdp|db@192.0.2.60#Production:ssh+database"
HOSTS+="|staging@192.0.2.70#Staging:ssh+database|pi@192.0.2.80#Home:ssh"
GLASS="--demo-glass 0.78,0.5,thin"
# The screen, in points: a 14-inch MacBook Pro's. The menu bar is a notched Mac's, 38 points, clear of the notch.
SCREEN_W=1512 SCREEN_H=982 MENU_BAR=38
mkdir -p "$RAW" "$OUT"
[[ -f "${BEZELS:-}/MacBook Pro M5 14-inch Space Black.png" && -f "${BEZELS:-}/MacBook Pro M5 14-inch Silver.png" ]] || {
  echo "site_shots: set BEZELS to the folder holding Apple's MacBook Pro M5 14-inch bezels (Space Black, Silver)" >&2; exit 1; }

gui() { timeout 90 $VM gui "$1"; }
events() { gui "osascript -e 'tell application \"System Events\" to $1'" >/dev/null 2>&1 || true; }
# The screen-recording notice macOS shows a capture from SSH, pressed away if it's up; and any other banner (macOS
# posts "See what's new in macOS Tahoe"), closed, so none stands over a picture.
notice() {
  timeout 60 $VM tool press UserNotificationCenter Allow >/dev/null 2>&1 || true
  gui "osascript '/Volumes/My Shared Files/macvm/close-banners.applescript'" >/dev/null 2>&1 || true
}

# The screen (2x), and the two desktop pictures in the VM. No desktop widgets (glass shows them), no Dock, the
# clock left where it is set (`screen` sets it), and no crash report left from an earlier run (it showed through
# the glass once, 2026-10-18).
prepare() {
  timeout 90 $VM tool display set ${SCREEN_W}x$SCREEN_H >/dev/null
  gui "defaults write com.apple.WindowManager StandardHideWidgets -bool true; killall NotificationCenter" >/dev/null 2>&1 || true
  dock hide
  timeout 60 $VM ssh "sudo systemsetup -setusingnetworktime off" >/dev/null 2>&1 || true
  # Keyboard navigation off, as a Mac ships: the Cirrus image turns it on for every control, and with it an editor
  # window's first tab wore a focus ring in every picture (2026-10-18 to 10-30). Read by each app as it launches.
  gui "defaults write -g AppleKeyboardUIMode -int 0" >/dev/null 2>&1 || true
  # Scroll bars while scrolling, as on a Mac with a trackpad: the VM has none, so macOS showed them always.
  gui "defaults write -g AppleShowScrollBars -string WhenScrolling" >/dev/null 2>&1 || true
  timeout 60 $VM tool press "Problem Reporter" OK >/dev/null 2>&1 || true
  python3 -I Tools/Screenshots/macvm/wallpaper.py "$RAW" $(( SCREEN_W * 2 ))x$(( SCREEN_H * 2 )) >/dev/null
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
# The Connections window is minimised, never closed with `--demo-close-connections`: with it, a terminal's window
# never opened (with a look, 2026-10-20; with btop, every launch after 2026-10-30's run of every shot), and closing
# it shows nothing more than minimising it does here, with the Dock hidden.
connections_away() { events "tell process \"$APP\" to set value of attribute \"AXMinimized\" of window \"All Connections\" to true"; }
alone() {  # title: that window in front, the app's others out of the way
  local title=$1
  [[ $title == "All Connections" ]] || connections_away
  raise "$title"
}
raise() {  # title: that window in front
  events "tell process \"$APP\" to set frontmost to true"
  events "tell process \"$APP\" to perform action \"AXRaise\" of window \"$1\""
  sleep 1
}
place() {  # w h: the front window's size, centred across the screen and a little above the middle below the menu bar
  local w=$1 h=$2
  timeout 90 $VM tool place "$APP" $(( (SCREEN_W - w) / 2 )) $(( MENU_BAR + (SCREEN_H - MENU_BAR - h) * 45 / 100 )) $w $h >/dev/null
  sleep 2
}
screen() {  # name: the whole screen, the clock at 9:41 as Apple's own pictures have it
  local name=$1
  timeout 60 $VM ssh 'sudo date "$(date +%m%d)0941" >/dev/null' >/dev/null 2>&1 || true
  sleep 2; notice
  gui "screencapture -x -t png /tmp/shot-screen.png"
  sleep 1; notice
  timeout 60 $VM ssh "cat /tmp/shot-screen.png && rm -f /tmp/shot-screen.png" > "$RAW/$name.png"
  if [[ $name == workspace-* ]]; then
    # Its own 1920 × 1200 screen, which no bezel has: the screen alone.
    python3 -I - "$RAW/$name.png" "$OUT/mac-$name.webp" <<'EOF'
import sys
from PIL import Image
screen = Image.open(sys.argv[1]).convert("RGB")
screen.save(sys.argv[2], "WEBP", quality=88, method=6)
print(f"{sys.argv[2]}: {screen.size[0]}x{screen.size[1]}")
EOF
    return
  fi
  local finish="Space Black"
  [[ $name == *-light ]] && finish="Silver"
  python3 -I Tools/Screenshots/bezel.py "$RAW/$name.png" "$BEZELS/MacBook Pro M5 14-inch $finish.png" "$OUT/macbook-$name.webp"
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
# shots put the Connections window away (`connections_away`); the library, Active and Workgroups are in it.
typeset -A SURFACE TITLE SIZE BEFORE
SURFACE=(library library-history  terminal btop  database database  diagram diagram  desktop desktop  editor editor
         editor-git editor-git  active active  workgroups workgroups)
TITLE=(library "All Connections"  terminal "alpha"  database "orders"  diagram "main"  desktop "bravo"
       editor "ShippingAddress.swift"  editor-git "Changes"  active "Active"  workgroups "Workgroups")
SIZE=(library "1200 740"  terminal "1240 780"  database "1240 780"  diagram "1240 780"  desktop "1240 780"
      editor "1240 780"  editor-git "1240 780"  active "1100 720"  workgroups "1240 780")
# The demo's desktop has no remote machine behind it, so the Caps Lock state it sends as its window becomes key is
# refused, and the window says the session isn't ready (as it should for a real one): dismissed before the picture.
# The terminal's sidebar is closed, as the owner keeps his (2026-10-30): open, it listed one terminal over an empty
# column. A window's sidebar stays as the last run left it, so it is closed, not left.
BEFORE=(terminal "hide-sidebar"  desktop "dismiss")
# `workspace`: its four windows by title, and each one's frame (x y w h, points): tiles on a 1920 × 1200 screen,
# which it has for its picture. 570 points high: the editor's least. The desktop keeps
# its remote screen's shape, so it is narrower, to stay that high.
WORKSPACE_TITLES=("alpha" "orders" "bravo" "ShippingAddress.swift")
WORKSPACE_FRAMES=("24 38 924 570" "972 38 924 570" "56 620 860 570" "972 620 924 570")
# `sql`: SQL from a terminal. A coding agent's query in alpha's terminal, its sidebar closed so the query shows, and,
# in front of it, the database window with that query in its editor, as Open in SQL Editor puts it there, then run
# as a person runs it: the sidebar's `main` opened, the editor's divider dragged down until the whole query shows,
# Run Statement pressed. The points
# are measured on these frames: the disclosure 26,114 from the window's corner; the divider 230 down, centred over
# the results (the sidebar is 348 wide).
SQL_TITLES=("✳ Claude Code" "orders")
SQL_FRAMES=("24 330 640 470" "580 56 900 840")
sql() {  # dark | light
  SETTLE=20 launch database-sql
  connections_away
  for i in {1..${#SQL_TITLES}}; do
    timeout 90 $VM tool place "$APP" ${=SQL_FRAMES[$i]} "${SQL_TITLES[$i]}" >/dev/null
  done
  timeout 60 $VM tool press "$APP" "Hide Sidebar" "${SQL_TITLES[1]}" >/dev/null 2>&1 || true
  raise "${SQL_TITLES[1]}"; raise "${SQL_TITLES[2]}"
  local -a frame=(${=SQL_FRAMES[2]})
  local x=${frame[1]} y=${frame[2]} w=${frame[3]}
  timeout 90 $VM tool click $(( x + 26 )) $(( y + 114 )) >/dev/null
  timeout 90 $VM tool drag $(( x + (348 + w) / 2 )) $(( y + 230 )) $(( x + (348 + w) / 2 )) $(( y + 295 )) >/dev/null
  timeout 60 $VM tool press "$APP" "Run Statement" >/dev/null
  sleep 3
  screen "sql-$1"
}
# `all-windows`: Show All Windows over what the `all-windows` surface opens (a terminal window of three tabs, the
# first running the btop-style monitor; the shop's database; a desktop; the editor), opened as a person opens it,
# from the terminal window's toolbar. It covers the whole screen, so the windows' frames under it don't matter. The
# desktop's not-ready notice (`BEFORE`) is dismissed first, or its picture would carry it. A tab has a picture once
# it has been shown, so each is shown (⌘2, ⌘3, then ⌘1 back to the monitor) before it opens.
all_windows() {  # dark | light
  SETTLE=24 launch all-windows
  connections_away
  timeout 60 $VM tool press "$APP" "Dismiss" >/dev/null 2>&1 || true
  sleep 1
  # Its accessibility name is the tab's and where it is connected ("alpha – ann@192.0.2.10:22"), so not `raise`.
  events "tell process \"$APP\" to set frontmost to true"
  events "tell process \"$APP\" to perform action \"AXRaise\" of (first window whose name starts with \"alpha\")"
  sleep 1
  for tab in 2 3 1; do
    events "keystroke \"$tab\" using command down"
    sleep 2
  done
  timeout 60 $VM tool press "$APP" "Show All Windows" alpha >/dev/null
  sleep 3
  screen "all-windows-$1"
}
dock() {  # hide | show: in the GUI session (from SSH alone the Dock stayed, 2026-10-30)
  gui "defaults write com.apple.dock autohide -bool $([[ $1 == hide ]] && echo true || echo false); killall Dock" >/dev/null 2>&1 || true
  sleep 3
}
# `looks`: the terminal's looks (D84), each over the btop-style monitor, as mac-look-<name>.webp. A look draws its
# own colours, so each is taken once, in the dark appearance. `--demo-look` takes a Start From look, or `none` with
# settings after it; `picture` puts the made-up landscape (landscape.py) behind the text, with Readability low
# enough for the landscape to show; `settings` is This Window open on a terminal in Digital Rain, its form scrolled
# to the Look section; `agent` is Coding Agent over a made-up agent session (the `agent` surface). Connections is minimised, not closed: with `--demo-close-connections` and `--demo-look`
# together no terminal window opened (2026-10-20). LOOKS="picture settings" takes only those.
typeset -A LOOK
LOOK=(rain digitalRain  synthwave synthwave  amber amberPhosphor  green greenPhosphor
      picture "none,intensity=1,readability=0.15,glow=0.3,glowColor=amber"  settings digitalRain
      agent agent  aurora aurora  starfield starfield  blueprint blueprint)
LOOK_NAMES=(${=LOOKS:-rain synthwave amber green picture settings agent aurora starfield blueprint})
looks() {
  python3 -I Tools/Screenshots/landscape.py "$RAW/landscape.png" >/dev/null
  timeout 60 $VM copy-in "$RAW/landscape.png" /Users/admin/Pictures >/dev/null
  appearance dark
  for look in $LOOK_NAMES; do
    local -a extra=()
    # The agent's window takes the title the agent gives its terminal.
    local title=alpha
    [[ $look == agent ]] && title="✳ Claude Code"
    [[ $look == picture ]] && extra=(--demo-picture /Users/admin/Pictures/landscape.png)
    if [[ $look == settings ]]; then
      SETTLE=16 launch terminal --demo-look "'${LOOK[$look]}'" --demo-look-settings
    elif [[ $look == agent ]]; then
      # A coding agent at work, which the look shows behind it.
      SETTLE=16 launch agent --demo-look "'${LOOK[$look]}'"
    else
      SETTLE=16 launch btop --demo-look "'${LOOK[$look]}'" $extra
    fi
    alone "$title"
    place 1240 780
    if [[ $look == settings ]]; then
      events "tell process \"$APP\" to set value of scroll bar 1 of scroll area 1 of group 1 of sheet 1 of window 1 to 0.36"
      sleep 2
    fi
    capture "look-$look" "$title"
  done
}

names=("$@")
# `workgroups` and `workspace` are there to name, not in the default set: the Mac's workgroup detail cuts its
# table off at this size, so the site shows the Vision Pro one; and the four windows at once repeated the home
# page's four service pictures, so the owner kept those (2026-10-18).
(( $# )) || names=(library terminal database diagram desktop editor editor-git sql active all-windows)
prepare
[[ -n ${(M)names:#database} || -n ${(M)names:#diagram} || -n ${(M)names:#workspace} || -n ${(M)names:#sql}
   || -n ${(M)names:#all-windows} ]] && shop
for name in $names; do
  [[ $name == looks ]] && { looks; continue; }
  [[ -n ${SURFACE[$name]:-} || $name == workspace || $name == sql || $name == all-windows ]] \
    || { echo "unknown shot: $name"; exit 2; }
  for look in dark light; do
    appearance $look
    if [[ $name == sql ]]; then
      sql $look
      continue
    fi
    if [[ $name == all-windows ]]; then
      all_windows $look
      continue
    fi
    if [[ $name == workspace ]]; then
      timeout 90 $VM tool display set 1920x1200 >/dev/null
      SETTLE=26 launch workspace
      connections_away
      raise "${WORKSPACE_TITLES[1]}"
      for i in {1..${#WORKSPACE_TITLES}}; do
        timeout 90 $VM tool place "$APP" ${=WORKSPACE_FRAMES[$i]} "${WORKSPACE_TITLES[$i]}" >/dev/null
        sleep 1
      done
      timeout 60 $VM tool press "$APP" "Dismiss" >/dev/null 2>&1 || true
      sleep 2
      screen "$name-$look"
      timeout 90 $VM tool display set ${SCREEN_W}x$SCREEN_H >/dev/null
      continue
    fi
    launch ${SURFACE[$name]}
    alone "${TITLE[$name]}"
    place ${=SIZE[$name]}
    if [[ ${BEFORE[$name]:-} == hide-sidebar ]]; then
      timeout 60 $VM tool press "$APP" "Hide Sidebar" "${TITLE[$name]}" >/dev/null 2>&1 || true
      sleep 2
      place ${=SIZE[$name]}
    elif [[ ${BEFORE[$name]:-} == dismiss ]]; then
      timeout 60 $VM tool press "$APP" "Dismiss" >/dev/null 2>&1 || true
      sleep 2
    fi
    screen "$name-$look"
  done
done
timeout 60 $VM quit-app >/dev/null 2>&1 || true
appearance light
