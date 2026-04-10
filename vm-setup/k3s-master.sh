#!/bin/bash
set -euo pipefail

echo 'vagrant ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/vagrant

# Pin resolver upstreams persistently. VirtualBox DHCP DNS can be flaky and
# causes intermittent registry lookup failures.
mkdir -p /etc/systemd/resolved.conf.d
cat >/etc/systemd/resolved.conf.d/99-k8s-lab.conf <<'EOF'
[Resolve]
DNS=8.8.8.8 1.1.1.1
FallbackDNS=9.9.9.9 8.8.4.4
EOF
rm -f /etc/netplan/99-k3s-worker-lab-dns.yaml
systemctl restart systemd-resolved

# Configure insecure mirror for the local registry before k3s starts
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml <<'EOF'
mirrors:
  "192.168.56.10:5000":
    endpoint:
      - "http://192.168.56.10:5000"
EOF

# Resolve the network interface that owns the host-only IP so flannel builds
# its VXLAN tunnel on the right NIC. --node-ip alone is not enough on
# multi-NIC VirtualBox VMs; --flannel-iface is required.
FLANNEL_IFACE=$(ip -o addr show | grep 192.168.56.11 | awk '{print $2}')

# Install K3s on the master node with readable kubeconfig.
# --advertise-address and --node-ip force k3s to bind to the private network
# interface instead of VirtualBox's NAT interface (eth0).
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --tls-san 192.168.56.11 \
  --advertise-address 192.168.56.11 \
  --node-ip 192.168.56.11 \
  --flannel-iface "$FLANNEL_IFACE" \
  --disable servicelb \
  --disable traefik

# Make sure kubectl is set up for the vagrant user
sudo mkdir -p /home/vagrant/.kube
sudo cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
sudo chown -R vagrant:vagrant /home/vagrant/.kube/config

# Get the token for the worker nodes
TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)

# Store the token for the workers to use
echo $TOKEN > /vagrant/token

# Export kubeconfig with the master's static IP so the runner VM can reach the API server
sed 's|https://127.0.0.1:6443|https://192.168.56.11:6443|g' /etc/rancher/k3s/k3s.yaml > /vagrant/kubeconfig
chmod 644 /vagrant/kubeconfig