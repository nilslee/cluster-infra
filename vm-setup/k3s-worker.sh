#!/bin/bash
# Get the master node's IP from the arguments
MASTER_IP=$1

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