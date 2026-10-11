#!/bin/bash
# One screenshot of one surface on one booted simulator, from a demo launch of the installed app.
#   APP=<path to the built .app> Tools/Screenshots/shoot.sh <simulator-udid> <surface> <out.png> [seconds]
# The app is reinstalled first: visionOS restores a previous launch's windows, which would stand in
# front of the one being captured.
# Surfaces: library, library-history, editor, editor-window, editor-settings, editor-project, preview,
# terminal, terminal-window, terminal-settings, terminal-move, terminal-tabs, terminal-grid, files, database,
# database-window, database-settings, database-server, database-main, diagram,
# desktop, desktop-window, desktop-settings, desktop-displays, desktop-quality, connections-host, orb,
# orb-looked-at, orb-later, orb-later-desktop
# (see App/GlassDemoMode.swift). The orb surfaces need DEMO_ARGS="--demo-idle-seconds 5".
set -euo pipefail
SIM="$1"; SURFACE="$2"; OUT="$3"; SETTLE="${4:-8}"
HOSTS="alpha@192.0.2.10:ssh+database|bravo@192.0.2.20:ssh+rdp|nas@192.0.2.30:ssh|build@192.0.2.40:ssh|win@192.0.2.50:rdp"
xcrun simctl terminate "$SIM" com.glasspowertools >/dev/null 2>&1 || true
if [ -n "${APP:-}" ]; then
  xcrun simctl uninstall "$SIM" com.glasspowertools >/dev/null 2>&1 || true
  xcrun simctl install "$SIM" "$APP"
fi
# The database surface opens a made-up shop, built fresh and placed in the app's Documents.
if [ "${SURFACE%%-*}" = "database" ] || [ "$SURFACE" = "diagram" ]; then
  DATA="$(xcrun simctl get_app_container "$SIM" com.glasspowertools data)"
  mkdir -p "$DATA/Documents"
  python3 "$(dirname "$0")/make-demo-db.py" "$DATA/Documents/demo-shop.sqlite" >/dev/null
fi
xcrun simctl launch "$SIM" com.glasspowertools --ui-testing "$(uuidgen)" \
  --ui-testing-seed-hosts "$HOSTS" --demo-open "$SURFACE" ${DEMO_ARGS:-} >/dev/null
sleep "$SETTLE"
xcrun simctl io "$SIM" screenshot "$OUT" >/dev/null 2>&1
echo "shoot: $SURFACE → $OUT"
