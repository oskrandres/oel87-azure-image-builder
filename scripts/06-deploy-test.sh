#!/usr/bin/env bash
# =============================================================================
# 06-deploy-test.sh   (run on your workstation, needs: az CLI logged in)
# Deploys a VM from the published image and validates provisioning + config.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-config.sh"

TEST_VM="${TEST_VM:-oel-test}"
TEST_PWD="${TEST_PWD:-ClaveFuerte#2026}"

IMG=$(az sig image-version show -g "$RG" --gallery-name "$GALLERY" \
  --gallery-image-definition "$IMAGE_DEF" --gallery-image-version "$IMAGE_VERSION" --query id -o tsv)

echo ">> Deploying $TEST_VM from $IMG"
az vm create -g "$RG" -n "$TEST_VM" --image "$IMG" \
  --size Standard_D2s_v3 --admin-username "$BUILDER_ADMIN" \
  --admin-password "$TEST_PWD" --public-ip-sku Standard \
  --os-disk-delete-option Delete --no-wait -o none

echo ">> Polling provisioning state (should reach 'Provisioning succeeded' in ~3-5 min)"
for i in $(seq 1 30); do
  sleep 20
  PROV=$(az vm get-instance-view -g "$RG" -n "$TEST_VM" \
     --query "instanceView.statuses[?starts_with(code,'ProvisioningState')].displayStatus | [0]" -o tsv 2>/dev/null || true)
  echo "   [$i] prov=$PROV"
  [ "$PROV" = "Provisioning succeeded" ] && break
  [ "$PROV" = "Provisioning failed" ] && { echo "FAILED"; exit 1; }
done

echo ">> In-guest validation"
az vm run-command invoke -g "$RG" -n "$TEST_VM" --command-id RunShellScript \
  --scripts "cat /etc/oracle-release; ip -4 addr show eth0 | grep inet; swapon --show; getenforce; id oracle; systemctl is-active waagent" \
  --query "value[0].message" -o tsv
