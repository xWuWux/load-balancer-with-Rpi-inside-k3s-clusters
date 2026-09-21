#!/usr/bin/env bash
# setup-node.sh -- run on every Raspberry Pi that will join the fog (k3s) cluster.
# Does NOT run on edge-lb1/edge-lb2 (those only need HAProxy + keepalived).
#
# Usage:
#   sudo ./setup-node.sh prep                          # step 1, every node, then REBOOT
#   sudo ./setup-node.sh server                        # step 2, first control-plane node only
#   sudo ./setup-node.sh agent   <server-ip> <token>   # step 2, worker nodes
#   sudo ./setup-node.sh server-ha <server-ip> <token> # optional: additional HA control-plane node
#
# Get <token> from the first server after it's up:
#   sudo cat /var/lib/rancher/k3s/server/node-token
#
# Corrects, versus the original project:
#   - no such thing as `k3s server join` (errata #1) -- real k3s uses
#     K3S_URL/K3S_TOKEN env vars for agents, and `server --server ...` for
#     additional control-plane nodes.
#   - the original never mentioned the Raspberry Pi memory-cgroup
#     requirement at all (errata #2); step "prep" below handles it.
set -euo pipefail

ROLE="${1:-}"

# ---------------------------------------------------------------------------
# Step 1: run on EVERY fog node (server and agents), then reboot before
# doing anything else.
# ---------------------------------------------------------------------------
prep() {
    echo "== updating base OS =="
    apt-get update && apt-get -y upgrade

    echo "== disabling swap (kubelet expects this; k3s will warn/degrade otherwise) =="
    if dpkg -l dphys-swapfile >/dev/null 2>&1; then
        systemctl disable --now dphys-swapfile || true
        apt-get -y purge dphys-swapfile || true
    fi

    echo "== enabling memory cgroup (required by kubelet, NOT on by default on Raspberry Pi OS) =="
    CMDLINE=""
    if [ -f /boot/firmware/cmdline.txt ]; then
        CMDLINE=/boot/firmware/cmdline.txt        # Raspberry Pi OS Bookworm and newer
    elif [ -f /boot/cmdline.txt ]; then
        CMDLINE=/boot/cmdline.txt                 # older Raspberry Pi OS releases
    else
        echo "!! could not find cmdline.txt -- edit your boot config manually" >&2
        exit 1
    fi

    if ! grep -q "cgroup_memory=1" "$CMDLINE"; then
        cp "$CMDLINE" "${CMDLINE}.bak.$(date +%s)"
        # cmdline.txt is ONE line, space-separated -- append, don't add a newline.
        sed -i -E 's/$/ cgroup_memory=1 cgroup_enable=memory/' "$CMDLINE"
        echo ">> added cgroup params to $CMDLINE (backup saved alongside it)"
    else
        echo ">> cgroup params already present in $CMDLINE"
    fi

    echo
    echo "!! REBOOT NOW, then re-run this script with 'server' / 'agent' / 'server-ha'."
    echo "!! After reboot, verify BEFORE installing k3s:"
    echo "     cat /proc/cgroups | awk '\$1==\"memory\"{print}'   # last column must be 1"
    echo "!! If it still reads 0 on a Raspberry Pi 5, this is a known firmware-dependent"
    echo "   issue (see raspberrypi/linux#5933) -- try 'sudo rpi-eeprom-update -a' and"
    echo "   reboot again, or fall back to a Pi 4B for that node."
}

# ---------------------------------------------------------------------------
# Step 2a: first control-plane node.
# ---------------------------------------------------------------------------
install_server() {
    check_cgroup
    echo "== installing k3s (first server) =="
    # servicelb disabled: external HAProxy+keepalived is the load balancer for
    # this project, so the in-cluster Klipper ServiceLB would just be a second,
    # redundant, weaker one (errata #4/#8). Traefik is left ENABLED and
    # reconfigured to NodePort via k8s/05-traefik-config.yaml -- it's doing a
    # real job here (in-cluster L7 host routing), unlike the original's
    # from-scratch HAProxy-inside-k3s Deployment.
    curl -sfL https://get.k3s.io | sh -s - server \
        --write-kubeconfig-mode 644 \
        --disable servicelb \
        --tls-san "$(hostname -I | awk '{print $1}')"

    echo "== node token for agents/HA servers (copy this) =="
    sleep 5
    cat /var/lib/rancher/k3s/server/node-token
}

# ---------------------------------------------------------------------------
# Step 2b: worker (agent) node.
# ---------------------------------------------------------------------------
install_agent() {
    local server_ip="$1" token="$2"
    check_cgroup
    echo "== installing k3s (agent, joining https://${server_ip}:6443) =="
    curl -sfL https://get.k3s.io | K3S_URL="https://${server_ip}:6443" K3S_TOKEN="${token}" sh -
}

# ---------------------------------------------------------------------------
# Step 2c (optional): additional control-plane node for HA (embedded etcd).
# Only needed if you extend this project beyond the 1-server/2-agent layout.
# ---------------------------------------------------------------------------
install_server_ha() {
    local server_ip="$1" token="$2"
    check_cgroup
    echo "== installing k3s (additional server, joining https://${server_ip}:6443) =="
    curl -sfL https://get.k3s.io | K3S_TOKEN="${token}" sh -s - server \
        --server "https://${server_ip}:6443" \
        --disable servicelb
}

check_cgroup() {
    local mem_enabled
    mem_enabled="$(awk '$1=="memory"{print $NF}' /proc/cgroups || echo 0)"
    if [ "$mem_enabled" != "1" ]; then
        echo "!! memory cgroup is not enabled (/proc/cgroups shows memory=$mem_enabled)." >&2
        echo "!! Run '$0 prep' and reboot first -- k3s/kubelet will not run correctly." >&2
        exit 1
    fi
}

case "$ROLE" in
    prep)        prep ;;
    server)      install_server ;;
    agent)       install_agent "${2:?server ip required}" "${3:?token required}" ;;
    server-ha)   install_server_ha "${2:?server ip required}" "${3:?token required}" ;;
    *)
        echo "Usage: $0 {prep|server|agent <server-ip> <token>|server-ha <server-ip> <token>}" >&2
        exit 1
        ;;
esac
