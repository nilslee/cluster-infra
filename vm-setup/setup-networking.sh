#!/bin/bash
set -euo pipefail

export KUBECONFIG=/vagrant/kubeconfig

# --- MetalLB ---

kubectl apply -f /networking/ns-metalb-system.yaml

helm repo add metallb https://metallb.github.io/metallb
helm repo update

helm upgrade --install metallb metallb/metallb \
  -n metallb-system \
  -f /networking/metallb-values.yaml \
  --wait --timeout 90s

# CRDs must be fully registered before we can create IPAddressPool / L2Advertisement.
# --wait covers the pods, but the webhook may need a moment.
kubectl wait --for=condition=Available deployment/metallb-controller \
  -n metallb-system --timeout=60s

# Retry loop: the validating webhook sometimes takes a few seconds after the
# controller reports Available.
for i in $(seq 1 10); do
  if kubectl apply -f /networking/metallb-pool.yaml; then
    break
  fi
  echo "MetalLB CRDs not ready yet, retrying in 5s... ($i/10)"
  sleep 5
done

# --- NGINX Ingress Controller ---

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f /networking/nginx-ingress-values.yaml \
  --wait --timeout 120s

# Show the external IP assigned by MetalLB
EXTERNAL_IP=$(kubectl get svc ingress-nginx-controller \
  -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

echo "----------------------------------------------"
echo "Networking stack deployed."
echo "  MetalLB pool : 192.168.56.200-192.168.56.220"
echo "  NGINX Ingress: ${EXTERNAL_IP:-<pending>}"
echo "----------------------------------------------"
