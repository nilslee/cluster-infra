#!/bin/bash
set -euo pipefail

export KUBECONFIG=/vagrant/kubeconfig

kubectl apply -f /dashboard/ns-dashboard.yaml

helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update

helm upgrade --install headlamp headlamp/headlamp \
  -n dashboard \
  -f /dashboard/headlamp-values.yaml

echo "Headlamp deployed. Dashboard: http://<any-node-ip>:30090 (e.g. 192.168.56.12:30090)"
