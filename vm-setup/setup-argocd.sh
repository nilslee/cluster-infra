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

echo "Argo CD deployed. UI: http://argocd.k8s.lab (via NGINX Ingress)"
echo "Initial admin password: ${ARGOCD_PASSWORD}"
echo "Log in and change the password via Settings → Account → Update Password."
