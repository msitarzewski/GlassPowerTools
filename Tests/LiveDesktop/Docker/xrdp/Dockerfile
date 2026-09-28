FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends xrdp xorgxrdp xserver-xorg-core openbox xterm xclip dbus-x11 openssl ca-certificates fonts-dejavu-core && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --shell /bin/bash glassfixture && mkdir -p /run/xrdp /tmp/.X11-unix /home/glassfixture/.config/openbox && chmod 1777 /tmp/.X11-unix
RUN printf '%s\n' 'xterm -geometry 90x26+40+40 -title "Glass Power Tools RDP Fixture" &' > /home/glassfixture/.config/openbox/autostart && chown -R glassfixture:glassfixture /home/glassfixture/.config
RUN printf '%s\n' '#!/bin/sh' 'unset DBUS_SESSION_BUS_ADDRESS' 'unset XDG_RUNTIME_DIR' 'exec dbus-run-session -- openbox-session' > /etc/xrdp/startwm.sh && chmod 755 /etc/xrdp/startwm.sh
RUN sed -i 's/^security_layer=.*/security_layer=tls/; s/^crypt_level=.*/crypt_level=high/' /etc/xrdp/xrdp.ini
COPY entrypoint.sh /usr/local/bin/glass-entrypoint
RUN chmod 755 /usr/local/bin/glass-entrypoint
EXPOSE 3389
ENTRYPOINT ["/usr/local/bin/glass-entrypoint"]
