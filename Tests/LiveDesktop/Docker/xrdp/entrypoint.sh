#!/bin/sh
set -eu
test -f /run/glass-test-password
test_password=$(cat /run/glass-test-password)
printf 'glassfixture:%s\n' "$test_password" | chpasswd
unset test_password
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 -subj '/CN=glass-isolated-fixture' -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem >/dev/null 2>&1
chown xrdp:xrdp /etc/xrdp/key.pem /etc/xrdp/cert.pem
chmod 600 /etc/xrdp/key.pem
mkdir -p /run/xrdp
chown xrdp:xrdp /run/xrdp
/usr/sbin/xrdp-sesman --nodaemon &
exec /usr/sbin/xrdp --nodaemon
