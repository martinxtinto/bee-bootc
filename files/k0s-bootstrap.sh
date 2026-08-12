#!/bin/bash
set -euo pipefail

TOKEN_FILE=/etc/k0s/join-token

# Already installed — nothing to do (idempotent across reboots)
if systemctl is-enabled --quiet k0scontroller; then
    exit 0
fi

if [ -s "$TOKEN_FILE" ]; then
    # Token present and non-empty: join existing cluster as controller+worker
    k0s install controller --enable-worker --no-taints --token-file="$TOKEN_FILE"
else
    # No token: this is the first node — bootstrap the cluster
    k0s install controller --enable-worker --no-taints
fi

systemctl enable --now k0scontroller
