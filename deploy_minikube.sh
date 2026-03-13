#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# build inside the same docker daemon as minikube to avoid pushing built images to dockerhub
eval $(minikube docker-env)

# 1) Build my-redis image
cd "$ROOT/my-redis"
minikube image build -t my-redis .

# 2) (TODO Uncomment) Build sidecar (if separate image)
# minikube image build -t my-redis-sidecar -f Dockerfile.sidecar .

# 3) (TODO Uncomment) Build redis-gui-tester image
# cd "$ROOT/redis-gui-tester"
# minikube image build -t redis-gui-tester .

# 4) Apply Kubernetes manifests from cluster-infra
cd "$ROOT/cluster-infra"
kubectl apply -f k8s/namespaces/
kubectl apply -f k8s/my-redis/
# kubectl apply -f k8s/redis-gui-tester/
