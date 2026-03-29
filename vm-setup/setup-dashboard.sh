#!/bin/bash
set -euo pipefail

export KUBECONFIG=/vagrant/kubeconfig

kubectl apply -f /dashboard/ns-dashboard.yaml

helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update

helm upgrade --install headlamp headlamp/headlamp \
  -n dashboard \
  -f /dashboard/headlamp-values.yaml

kubectl apply -f /dashboard/headlamp-ingress.yaml

echo "Headlamp deployed. Dashboard: http://headlamp.k8s.lab (via NGINX Ingress)"
