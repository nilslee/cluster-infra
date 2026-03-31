#!/bin/bash
set -euo pipefail

export KUBECONFIG=/vagrant/kubeconfig

kubectl apply -f /argocd/ns-argocd.yaml

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd \
  argo/argo-cd \
  -n argocd \
  -f /argocd/argocd-values.yaml

# Wait for the server to be ready before applying the Ingress and Applications.
kubectl rollout status deployment/argocd-server -n argocd --timeout=120s

kubectl apply -f /argocd/argocd-ingress.yaml
kubectl apply -f /argocd/applications/namespaces.yaml
kubectl apply -f /argocd/applications/my-redis.yaml

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

# ── /etc/hosts entry so argocd CLI can resolve argocd.k8s.lab ────────────────
# 192.168.56.200 is the MetalLB VIP assigned to the NGINX Ingress Controller.
if ! grep -q "argocd.k8s.lab" /etc/hosts; then
  echo "192.168.56.200 argocd.k8s.lab" >> /etc/hosts
fi

# ── Wait for the ArgoCD server to be reachable through the Ingress ────────────
echo "Waiting for ArgoCD server to be reachable at argocd.k8s.lab..."
for i in $(seq 1 30); do
  if argocd login argocd.k8s.lab \
      --insecure --grpc-web \
      --username admin \
      --password "${ARGOCD_PASSWORD}" \
      2>/dev/null; then
    echo "ArgoCD login succeeded."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: ArgoCD server did not become reachable after 150 s." >&2
    exit 1
  fi
  echo "  attempt $i/30 failed, retrying in 5s..."
  sleep 5
done

# ── Generate a long-lived API token for the admin account ────────────────────
# The account service can return 502 for a short window after login starts
# working, so retry until the token is successfully issued.
echo "Generating ArgoCD API token..."
ARGOCD_AUTH_TOKEN=""
for i in $(seq 1 20); do
  ARGOCD_AUTH_TOKEN=$(argocd account generate-token \
    --account admin \
    --insecure --grpc-web 2>/dev/null || true)
  if [ -n "${ARGOCD_AUTH_TOKEN}" ]; then
    echo "Token generated successfully."
    break
  fi
  if [ "$i" -eq 20 ]; then
    echo "ERROR: Failed to generate ArgoCD API token after 100 s." >&2
    exit 1
  fi
  echo "  attempt $i/20 failed (server not fully ready), retrying in 5s..."
  sleep 5
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo " Argo CD provisioning complete"
echo "============================================================"
echo " UI:                http://argocd.k8s.lab"
echo " Username:          admin"
echo " Initial password:  ${ARGOCD_PASSWORD}"
echo ""
echo " ARGOCD_AUTH_TOKEN: ${ARGOCD_AUTH_TOKEN}"
echo "============================================================"
echo ""
echo "Next steps:"
echo "  1. Open https://github.com/<your-org>/cluster-infra/settings/secrets/actions"
echo "  2. Click 'New repository secret'"
echo "  3. Name:  ARGOCD_AUTH_TOKEN"
echo "  4. Value: (paste the token printed above)"
echo ""
echo "After adding the secret the cluster-infra apply.yml workflow will"
echo "be able to authenticate to ArgoCD automatically."
echo ""
echo "Optional: change the admin password via Settings → Account → Update Password,"
echo "then delete the bootstrap secret:"
echo "  kubectl delete secret argocd-initial-admin-secret -n argocd"
