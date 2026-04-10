#!/bin/bash
set -euo pipefail

# systemd-resolved + DHCP from VirtualBox often yields uplink DNS (e.g. home
# router) that is unreachable or broken from the guest, so github.com fails
# before Jenkins/git or curl in later provisioners run. Pin the NAT/default
# interface to public resolvers (same idea as setup-coredns-dns.sh for pods).

IFACE=$(ip -4 route show default | awk '{print $5; exit}')
if [[ -z "${IFACE}" ]]; then
  echo "No IPv4 default route; skipping guest DNS pin."
  exit 0
fi

NETPLAN_SNIPPET="/etc/netplan/99-runner-ci-lab-dns.yaml"
cat >"${NETPLAN_SNIPPET}" <<EOF
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4-overrides:
        use-dns: false
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF

netplan apply

if getent hosts github.com >/dev/null 2>&1; then
  echo "Guest DNS OK (${IFACE} -> 8.8.8.8 / 1.1.1.1); github.com resolves."
else
  echo "Warning: netplan applied but github.com still does not resolve; check routing."
  exit 1
fi
