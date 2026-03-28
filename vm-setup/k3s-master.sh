#!/bin/bash
echo 'vagrant ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/vagrant

# Configure insecure mirror for the local registry before k3s starts
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml <<'EOF'
mirrors:
  "192.168.56.10:5000":
    endpoint:
      - "http://192.168.56.10:5000"
EOF

# Install K3s on the master node with readable kubeconfig
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 --tls-san 192.168.56.11

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