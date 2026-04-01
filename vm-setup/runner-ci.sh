#!/bin/bash
set -euo pipefail

# ── Docker Engine ────────────────────────────────────────────────────────────
curl -fsSL https://get.docker.com | sh
usermod -aG docker vagrant

# ── Local container registry (registry:2) ────────────────────────────────────
# Exposed on 0.0.0.0:5000 so k3s nodes can pull via 192.168.56.10:5000
docker run -d \
  --restart=always \
  --name registry \
  -p 5000:5000 \
  registry:2

# ── kubectl ───────────────────────────────────────────────────────────────────
KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -fsSLo /tmp/kubectl \
  "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl"
install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
rm /tmp/kubectl

# Point kubectl at the kubeconfig written by k3s-master.sh
mkdir -p /home/vagrant/.kube
# kubeconfig is picked up at job time via KUBECONFIG=/vagrant/kubeconfig;
# symlink it here for interactive vagrant ssh sessions as well.
ln -sf /vagrant/kubeconfig /home/vagrant/.kube/config
chown -h vagrant:vagrant /home/vagrant/.kube/config

# ── Helm ────────────────────────────────────────────────────────────────────
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "runner-ci base provisioning complete."
echo "Jenkins is provisioned separately by setup-jenkins.sh."
