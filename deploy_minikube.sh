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

# 3) Build redis-gui-tester image
cd "$ROOT/redis-gui-tester"
minikube image build -t redis-gui-tester .

# 4) Apply Kubernetes manifests from cluster-infra
cd "$ROOT/cluster-infra"
kubectl apply -f k8s/namespaces/
kubectl apply -f k8s/my-redis/
kubectl apply -f k8s/redis-gui-tester/

# 5) Trigger rollouts ONLY if the image was actually updated
# We check if the rollout is needed by comparing the new local ID vs what's running
for DEP in "my-redis" "redis-gui-tester"; do
    LOCAL_ID=$(minikube image inspect $DEP:latest --format='{{.Id}}')
    RUNNING_ID=$(kubectl get deployment $DEP -o jsonpath='{.spec.template.metadata.annotations.image-id}' 2>/dev/null || echo "none")

    if [ "$LOCAL_ID" != "$RUNNING_ID" ]; then
        echo "Updating $DEP..."
        # We use an annotation to record the ID and force the rollout
        kubectl patch deployment $DEP -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"image-id\":\"$LOCAL_ID\"}}}}}"
    else
        echo "$DEP is already up to date."
    fi
done