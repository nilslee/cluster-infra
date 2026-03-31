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

# ── GitHub Actions Runner ─────────────────────────────────────────────────────
RUNNER_VERSION="2.322.0"
RUNNER_ARCH="arm64"
RUNNER_PKG="actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

# Download runner into the vagrant home directory
cd /home/vagrant
mkdir -p actions-runner && cd actions-runner

curl -fsSLo "${RUNNER_PKG}" \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_PKG}"

# Extract
tar xzf "${RUNNER_PKG}"
rm "${RUNNER_PKG}"
chown -R vagrant:vagrant /home/vagrant/actions-runner

# Configure and register the runner (run as the vagrant user).
# Replace <REPO_URL> and <TOKEN> before provisioning, or run manually after:
#   sudo -u vagrant ./config.sh --url <REPO_URL> --token <TOKEN> \
#     --name runner-ci --labels k8s-lab --unattended
#
# Then install and start as a systemd service:
#   sudo ./svc.sh install vagrant
#   sudo ./svc.sh start

# ── Helm ────────────────────────────────────────────────────────────────────
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ── ArgoCD CLI ───────────────────────────────────────────────────────────────
curl -sSL -o /usr/local/bin/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-arm64
chmod +x /usr/local/bin/argocd

echo "runner-ci provisioning complete."
echo "Next step: register the GitHub Actions runner (see comments in this script or VM_README.md)."
