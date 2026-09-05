#!/usr/bin/env bash
# =============================================================================
# 05-convert-upload.sh   (run ON the builder VM, as azureuser; needs az login)
# Converts qcow2 -> fixed VHD (1MB aligned) and uploads to a managed disk,
# then publishes an Azure Compute Gallery image version.
#
# Uploading from the builder (inside Azure) is fast and avoids egress.
# az login on the builder: use 'az login --use-device-code' or assign a
# managed identity with Contributor on the RG and 'az login --identity'.
# Alternatively create the disk + SAS from your workstation and only run the
# azcopy line here (see README).
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-config.sh"

echo ">> Convert qcow2 -> raw -> fixed VHD (1MB aligned, required by Azure)"
cd "$WORKDIR"
rm -f ol87.raw "$VHD"
qemu-img convert -f qcow2 -O raw "$QCOW" ol87.raw
MB=$((1024*1024))
SIZE=$(qemu-img info -f raw --output json ol87.raw | python3 -c 'import sys,json;print(json.load(sys.stdin)["virtual-size"])')
ROUND=$(( ( (SIZE + MB - 1) / MB ) * MB ))
qemu-img resize -f raw ol87.raw "$ROUND" >/dev/null
qemu-img convert -f raw -o subformat=fixed,force_size -O vpc ol87.raw "$VHD"
BYTES=$(stat -c %s "$VHD")
echo "   VHD bytes=$BYTES  footer=$(tail -c 512 "$VHD" | head -c 8)"   # must be 'conectix'

echo ">> Create upload-mode managed disk (Gen2/V2)"
az account set --subscription "$SUBSCRIPTION_ID"
az disk delete -g "$RG" -n "$OSDISK_NAME" --yes 2>/dev/null || true
az disk create -g "$RG" -n "$OSDISK_NAME" -l "$LOCATION" --os-type Linux \
  --hyper-v-generation V2 --upload-type Upload --upload-size-bytes "$BYTES" -o none

# The SAS field name differs across CLI versions: accessSAS or accessSas.
SAS=$(az disk grant-access -g "$RG" -n "$OSDISK_NAME" --access-level Write \
      --duration-in-seconds 86400 --query accessSAS -o tsv 2>/dev/null || true)
[ -z "$SAS" ] && SAS=$(az disk grant-access -g "$RG" -n "$OSDISK_NAME" --access-level Write \
      --duration-in-seconds 86400 --query accessSas -o tsv)
[ -z "$SAS" ] && { echo "ERROR: empty SAS. If disk is ActiveUpload, revoke-access then retry."; exit 1; }

echo ">> Upload VHD as page blob"
azcopy copy "$VHD" "$SAS" --blob-type PageBlob
az disk revoke-access -g "$RG" -n "$OSDISK_NAME" -o none    # seals & validates VHD

echo ">> Publish gallery image version"
az sig create -g "$RG" --gallery-name "$GALLERY" -o none 2>/dev/null || true
az sig image-definition create -g "$RG" --gallery-name "$GALLERY" \
  -i "$IMAGE_DEF" --publisher "$IMAGE_PUBLISHER" --offer "$IMAGE_OFFER" --sku "$IMAGE_SKU" \
  --os-type Linux --os-state Generalized --hyper-v-generation V2 \
  --features "SecurityType=Standard" -o none 2>/dev/null || true
DISKID=$(az disk show -g "$RG" -n "$OSDISK_NAME" --query id -o tsv)
az sig image-version create -g "$RG" --gallery-name "$GALLERY" \
  --gallery-image-definition "$IMAGE_DEF" --gallery-image-version "$IMAGE_VERSION" \
  --os-snapshot "$DISKID" -o none

echo "Published: $GALLERY/$IMAGE_DEF/$IMAGE_VERSION"
