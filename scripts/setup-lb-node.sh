#!/usr/bin/env bash
# setup-lb-node.sh -- run on edge-lb1 and edge-lb2 (NOT the fog/k3s nodes).
# Usage: sudo ./setup-lb-node.sh
#
# After this completes, copy the matching haproxy.cfg (identical on both
# nodes) to /etc/haproxy/haproxy.cfg, and keepalived-lb1-master.conf or
# keepalived-lb2-backup.conf (as appropriate for this box) to
# /etc/keepalived/keepalived.conf, then:
#   haproxy -c -f /etc/haproxy/haproxy.cfg   && systemctl restart haproxy
#   keepalived -t -f /etc/keepalived/keepalived.conf && systemctl restart keepalived
set -euo pipefail

echo "== installing haproxy + keepalived =="
apt-get update
apt-get install -y haproxy keepalived ufw fail2ban unattended-upgrades

echo "== dedicated unprivileged user for keepalived's health-check script =="
# Modern keepalived refuses to run any vrrp_script until script_security is
# enabled, and by default wants to run that script as this account rather
# than root -- see keepalived-lb1-master.conf's global_defs for why.
id keepalived_script >/dev/null 2>&1 || \
    useradd --system --no-create-home --shell /usr/sbin/nologin keepalived_script

echo "== firewall (see docs/SECURITY.md #3 for the fog-node side) =="
ufw default deny incoming
ufw allow 22/tcp
ufw allow 80,443,8883/tcp
ufw enable

echo "== done. Now copy over haproxy.cfg and the matching keepalived-lb*.conf,"
echo "   validate with 'haproxy -c' / 'keepalived -t', then restart both services."
