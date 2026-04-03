#!/bin/bash
set -euo pipefail

# CoreDNS ships with `forward . /etc/resolv.conf`. On VirtualBox host-only + NAT,
# the host's ISP/router DNS (e.g. 192.168.x.x, carrier resolvers) is often
# unreachable or flaky from the pod network, causing "server misbehaving" /
# timeouts for github.com and other external names.
export KUBECONFIG=/vagrant/kubeconfig

COREFILE=$(kubectl get cm coredns -n kube-system -o jsonpath='{.data.Corefile}')
if printf '%s' "$COREFILE" | grep -q 'forward \. 8.8.8.8'; then
  echo "CoreDNS already forwards to public resolvers; skipping."
  exit 0
fi

if ! printf '%s' "$COREFILE" | grep -q 'forward \. /etc/resolv.conf'; then
  echo "Corefile has no 'forward . /etc/resolv.conf'; not patching automatically."
  exit 0
fi

NODEHOSTS=$(kubectl get cm coredns -n kube-system -o jsonpath='{.data.NodeHosts}')
NEWCORE=$(printf '%s' "$COREFILE" | sed 's|forward \. /etc/resolv.conf|forward . 8.8.8.8 1.1.1.1|')

kubectl create configmap coredns -n kube-system \
  --from-literal=Corefile="$NEWCORE" \
  --from-literal=NodeHosts="$NODEHOSTS" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=120s
echo "CoreDNS now forwards to 8.8.8.8 and 1.1.1.1."
