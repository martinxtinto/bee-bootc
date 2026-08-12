#!/bin/bash
set -euo pipefail

AUTHKEY_FILE=/etc/tailscale/authkey
STATE_FILE=/var/lib/tailscale/tailscaled.state

# Already authed — nothing to do (idempotent across reboots)
if tailscale status >/dev/null 2>&1; then
    exit 0
fi

if [ -s "$AUTHKEY_FILE" ]; then
    tailscale up \
        --authkey="$(cat "$AUTHKEY_FILE")"
fi
