FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends tigervnc-standalone-server tigervnc-tools tigervnc-common openbox xterm xclip xdotool fonts-dejavu-core dbus-x11 && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --shell /bin/bash glassfixture && mkdir -p /home/glassfixture/.vnc /home/glassfixture/.config/openbox && chown -R glassfixture:glassfixture /home/glassfixture
RUN printf '%s\n' 'xterm -geometry 90x26+40+40 -title "Glass Power Tools VNC Fixture" &' > /home/glassfixture/.config/openbox/autostart && chown glassfixture:glassfixture /home/glassfixture/.config/openbox/autostart
COPY entrypoint.sh /usr/local/bin/glass-vnc-entrypoint
RUN chmod 755 /usr/local/bin/glass-vnc-entrypoint
EXPOSE 5900
ENTRYPOINT ["/usr/local/bin/glass-vnc-entrypoint"]
