#!/usr/bin/env bash
# =============================================================================
# 01-create-builder.sh  (run on your workstation, needs: az CLI logged in)
# Creates an x86_64 Azure VM with NESTED VIRTUALIZATION to build the image.
#
# Why a builder VM? Oracle Linux 8.7 is x86_64. Building on Apple Silicon /
# Windows-ARM means slow emulation and subtle boot problems. An Azure Dv3/Dsv3
# VM exposes VT-x (nested virt) so KVM runs the guest at native speed.
#
# Capacity tip: some regions/subscriptions reject sizes with SkuNotAvailable.
# This script tries a list of nested-virt-capable sizes until one succeeds.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-config.sh"

az account set --subscription "$SUBSCRIPTION_ID"
az group create -n "$RG" -l "$LOCATION" -o none

SIZES=("$BUILDER_SIZE" "Standard_D4s_v5" "Standard_D4as_v5" "Standard_D8s_v3" "Standard_F4s_v2")
created=""
for sz in "${SIZES[@]}"; do
  echo ">> Trying builder size $sz in $LOCATION ..."
  if az vm create -g "$RG" -n "$BUILDER_VM" \
        --image Ubuntu2204 --size "$sz" \
        --admin-username "$BUILDER_ADMIN" --generate-ssh-keys \
        --os-disk-size-gb 128 --public-ip-sku Standard -o none 2>/tmp/vmcreate.err; then
    created="$sz"; break
  else
    if grep -q "SkuNotAvailable" /tmp/vmcreate.err; then
      echo "   no capacity for $sz, trying next..."
    else
      cat /tmp/vmcreate.err; exit 1
    fi
  fi
done
[ -z "$created" ] && { echo "No nested-virt capacity found in $LOCATION. Try another region."; exit 1; }

IP=$(az vm show -g "$RG" -n "$BUILDER_VM" -d --query publicIps -o tsv)
echo "=============================================="
echo " Builder ready: $BUILDER_VM ($created)  IP=$IP"
echo " SSH: ssh $BUILDER_ADMIN@$IP"
echo "=============================================="
echo "$IP" > /tmp/builder_ip.txt
