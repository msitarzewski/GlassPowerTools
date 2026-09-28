#!/bin/bash
set -euo pipefail
# The VNC password is bind-mounted by run.sh; TigerVNC uses only its first eight bytes.
su glassfixture -c 'umask 077; vncpasswd -f < /run/glass-test-password > /home/glassfixture/.vnc/passwd'
exec su glassfixture -c 'cd /home/glassfixture && Xtigervnc :1 -geometry 1024x640 -depth 24 -rfbport 5900 -localhost no -AlwaysShared -SecurityTypes VncAuth -rfbauth /home/glassfixture/.vnc/passwd -desktop glass-vnc-fixture -AcceptSetDesktopSize & sleep 2; DISPLAY=:1 dbus-run-session -- openbox-session'
