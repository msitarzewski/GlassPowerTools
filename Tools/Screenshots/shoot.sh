#!/bin/bash
# One screenshot of one surface on one booted simulator, from a demo launch of the installed app.
#   APP=<path to the built .app> Tools/Screenshots/shoot.sh <simulator-udid> <surface> <out.png> [seconds]
# The app is reinstalled first: visionOS restores a previous launch's windows, which would stand in
# front of the one being captured.
# Surfaces: library, library-history, editor, editor-window, editor-settings, editor-project, preview,
# terminal, terminal-window, terminal-settings, terminal-move, terminal-tabs, terminal-grid, agent (a coding agent
# waiting for an answer), files, database,
# btop (the terminal running a btop-style monitor), workspace (it, a database, a desktop and the editor at
# once), active, workgroups,
# database-window, database-settings, database-server, database-main, diagram,
# desktop, desktop-window, desktop-settings, desktop-displays, desktop-quality, connections-host, orb,
# orb-looked-at, orb-later, orb-later-desktop, dock (Vision Pro: windows gathered into the orb dock, one beside it),
# editor-git, editor-history, editor-blame (the shop as a Git repository; `--demo-editor-size w,h` for a taller window),
# database-sql (a coding agent's SQL in a terminal, then in a query tab). DEMO_ORB_NAME="<title>" shows that orb's name, spaces and all.
# (see App/GlassDemoMode.swift). The orb surfaces need DEMO_ARGS="--demo-idle-seconds 5".
set -euo pipefail
SIM="$1"; SURFACE="$2"; OUT="$3"; SETTLE="${4:-8}"
. "$(dirname "$0")/demo-hosts.sh"
xcrun simctl terminate "$SIM" com.glasspowertools >/dev/null 2>&1 || true
if [ -n "${APP:-}" ]; then
  xcrun simctl uninstall "$SIM" com.glasspowertools >/dev/null 2>&1 || true
  xcrun simctl install "$SIM" "$APP"
fi
# Focus Mode's rooms (D89): the simulator has no iCloud to bring them, so the rooms asked for (DEMO_ENVIRONMENTS,
# paths separated by ":", each a room file or its .sounds or .events folder) go into the app's own environments folder.
if [ -n "${DEMO_ENVIRONMENTS:-}" ]; then
  ROOMS="$(xcrun simctl get_app_container "$SIM" com.glasspowertools data)/Library/Application Support/com.glasspowertools/Focus Environments"
  mkdir -p "$ROOMS"
  IFS=: read -ra ROOM_PATHS <<< "$DEMO_ENVIRONMENTS"
  for item in "${ROOM_PATHS[@]}"; do cp -R "$item" "$ROOMS/"; done
fi
# The database surface opens a made-up shop, built fresh and placed in the app's Documents.
if [ "${SURFACE%%-*}" = "database" ] || [ "$SURFACE" = "diagram" ] || [ "$SURFACE" = "workspace" ] || [ "$SURFACE" = "dock" ]; then
  DATA="$(xcrun simctl get_app_container "$SIM" com.glasspowertools data)"
  mkdir -p "$DATA/Documents"
  python3 "$(dirname "$0")/make-demo-db.py" "$DATA/Documents/demo-shop.sqlite" >/dev/null
fi
xcrun simctl launch "$SIM" com.glasspowertools --ui-testing "$(uuidgen)" \
  --ui-testing-seed-hosts "$HOSTS" --demo-open "$SURFACE" ${DEMO_ARGS:-} \
  ${DEMO_ORB_NAME:+--demo-orb-name "$DEMO_ORB_NAME"} >/dev/null
sleep "$SETTLE"
# SHOT_DISPLAY picks one display of a device with two, such as the iPhone Duo's outer ("1") or inner ("3").
xcrun simctl io "$SIM" screenshot ${SHOT_DISPLAY:+--display="$SHOT_DISPLAY"} "$OUT" >/dev/null 2>&1
echo "shoot: $SURFACE → $OUT"
