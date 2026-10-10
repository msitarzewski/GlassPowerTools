# W30: the TigerVNC fixture (../tigervnc), plus a picture workload for comparing bytes per second.
# A separate image on purpose: adding these packages to the base image made its keyboard check fail
# (2026-10-10, measured; the cause was not investigated), and the base image's checks stay as they were.
ARG BASE=glass-vnc-fixture:local
FROM ${BASE}
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends python3-tk && rm -rf /var/lib/apt/lists/*
COPY animate.py /usr/local/bin/glass-animate
RUN chmod 755 /usr/local/bin/glass-animate
