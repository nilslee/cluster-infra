#!/bin/bash
set -euo pipefail

export KUBECONFIG=/vagrant/kubeconfig

kubectl apply -f /monitoring/ns-monitoring.yaml

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f /monitoring/kube-prometheus-stack-values.yaml

helm upgrade --install loki \
  grafana/loki \
  -n monitoring \
  -f /monitoring/loki-values.yaml

helm upgrade --install promtail \
  grafana/promtail \
  -n monitoring \
  -f /monitoring/promtail-values.yaml

# Download community dashboards from GitHub and load them as ConfigMaps.
# The runner-ci VM has internet access; pods do not. The grafana-sc-dashboard
# sidecar watches for ConfigMaps labelled grafana_dashboard=1 and loads them
# into Grafana automatically.
DASHBOARD_REPO="https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards"
DASHBOARDS=(
  k8s-system-api-server
  k8s-system-coredns
  k8s-views-global
  k8s-views-namespaces
  k8s-views-nodes
  k8s-views-pods
)

for name in "${DASHBOARDS[@]}"; do
  curl -sfL "${DASHBOARD_REPO}/${name}.json" -o "/tmp/${name}.json"
  kubectl create configmap "grafana-dashboard-${name}" \
    -n monitoring \
    --from-file="${name}.json=/tmp/${name}.json" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl label configmap "grafana-dashboard-${name}" \
    -n monitoring grafana_dashboard=1 --overwrite
done

echo "Monitoring stack deployed. Grafana: http://192.168.56.12:30080"