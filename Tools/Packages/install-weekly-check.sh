#!/bin/sh
# Runs Tools/Packages/check-updates.py every Monday at 08:00 (or at the next wake, if the Mac was
# asleep): the survey, then tests against every direct dependency with a newer release. Reports go
# to ~/Library/Logs/GlassPowerTools/, with a notification when something is newer or a test fails.
# Nothing in the repository changes; raising a pin stays a person's decision.
#
#   install-weekly-check.sh            install, or reinstall after the checkout moves
#   install-weekly-check.sh --remove   remove
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
LABEL=com.glasspowertools.dependency-check
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGS="$HOME/Library/Logs/GlassPowerTools"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
if [ "${1:-}" = "--remove" ]; then
    rm -f "$PLIST"
    echo "install-weekly-check: removed"
    exit 0
fi

mkdir -p "$LOGS" "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$ROOT/Tools/Packages/check-updates.py</string>
        <string>--test</string><string>newer</string>
        <string>--report</string><string>$LOGS/</string>
        <string>--notify</string>
    </array>
    <key>WorkingDirectory</key><string>$ROOT</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>8</integer><key>Minute</key><integer>0</integer></dict>
    <key>ProcessType</key><string>Background</string>
    <key>LowPriorityIO</key><true/>
    <key>Nice</key><integer>10</integer>
    <key>StandardOutPath</key><string>$LOGS/dependency-check.log</string>
    <key>StandardErrorPath</key><string>$LOGS/dependency-check.log</string>
</dict>
</plist>
PLIST
plutil -lint "$PLIST" >/dev/null
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "install-weekly-check: runs Mondays at 08:00; reports in $LOGS"
