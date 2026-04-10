#!/bin/bash
set -euo pipefail

# Get the master node's IP from the arguments
MASTER_IP=$1

# Pin resolver upstreams persistently. VirtualBox DHCP DNS can be flaky and
# causes intermittent registry lookup failures (ImagePullBackOff).
mkdir -p /etc/systemd/resolved.conf.d
cat >/etc/systemd/resolved.conf.d/99-k8s-lab.conf <<'EOF'
[Resolve]
DNS=8.8.8.8 1.1.1.1
FallbackDNS=9.9.9.9 8.8.4.4
EOF
rm -f /etc/netplan/99-k3s-worker-lab-dns.yaml
systemctl restart systemd-resolved

# Get the token from the shared folder
TOKEN=$(cat /vagrant/token)

# Configure local registry mirror before k3s agent starts
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml <<'EOF'
mirrors:
  "192.168.56.10:5000":
    endpoint:
      - "http://192.168.56.10:5000"
EOF

# Detect this node's IP and interface on the private network by finding the
# source address / device used to reach the master. This avoids accidentally
# binding to VirtualBox's NAT interface (10.0.2.15) instead of the host-only
# interface (192.168.56.x).
NODE_IP=$(ip route get $MASTER_IP | grep -oP 'src \K[\d.]+')
FLANNEL_IFACE=$(ip route get $MASTER_IP | grep -oP 'dev \K\S+')

# Install K3s agent (worker) and join the master node
curl -sfL https://get.k3s.io | K3S_URL=https://$MASTER_IP:6443 K3S_TOKEN=$TOKEN sh -s - \
  --node-ip $NODE_IP \
  --flannel-iface "$FLANNEL_IFACE"