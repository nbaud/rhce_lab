#!/usr/bin/env bash
set -euo pipefail

# Repair labels on connection files created during network configuration.
restorecon -RF /etc/NetworkManager/system-connections

# The host-only network must not provide a default route.
lab_connection=$(nmcli -g GENERAL.CONNECTION device show enp0s8)

if [[ -z "$lab_connection" || "$lab_connection" == "--" ]]; then
    echo "No active NetworkManager connection found for enp0s8" >&2
    exit 1
fi

nmcli connection modify "$lab_connection" \
    ipv4.never-default yes \
    ipv4.gateway "" \
    ipv6.never-default yes

nmcli device reapply enp0s8

echo "Network preparation complete:"
ip -4 route
