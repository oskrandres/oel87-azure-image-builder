#!/usr/bin/env bash
# =============================================================================
# 03-generalize.sh   (run INSIDE the guest, as root — the LAST in-guest step)
# Generalizes the image with waagent. After this, DO NOT boot the VM again in
# Hyper-V (it would re-provision and remove the user). Power off, then convert
# the VHDX to a fixed VHD on Windows (04-convert-upload.ps1).
# =============================================================================
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }

# Keep SELinux enforcing safe: relabel on next boot in case any context drifted.
touch /.autorelabel

echo ">> Deprovisioning (removes user, host keys, leases, logs)..."
waagent -force -deprovision+user
export HISTSIZE=0
echo ">> Powering off. Convert the VHDX on Windows next."
poweroff
