#!/usr/bin/env bash
set -euo pipefail

# RUN THIS FIRST AFTER THIS REPO IS CLONED

# Script to clone application repos as SIBLING directories.
# my-redis
# my-redis-sidecar (listens to deployments/updates to trigger other actions)
# redis-gui-tester

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT/.."

[ -d my-redis ] || git clone git@github.com:you/my-redis.git
[ -d redis-gui-tester ] || git clone git@github.com:you/redis-gui-tester.git