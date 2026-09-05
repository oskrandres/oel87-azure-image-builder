#!/usr/bin/env bash
# =============================================================================
# 03-install-ol87.sh   (run ON the builder VM, as azureuser)
# Unattended kickstart install of Oracle Linux 8.7 into a qcow2 disk.
# Produces $QCOW with STANDARD partitions (no LVM), no swap, Gen2/UEFI.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-config.sh"

KS_SRC="$(dirname "$0")/../kickstart/ol87-azure.ks"
cp "$KS_SRC" /tmp/ol87-azure.ks

echo ">> Launching unattended kickstart install (this runs headless)"
sudo virt-install --name ol87 --ram 6144 --vcpus 4 \
  --os-variant ol8.7 --boot uefi \
  --disk path="$QCOW",size="$DISK_GB",bus=scsi,format=qcow2 \
  --location "$WORKDIR/OL87.iso" \
  --initrd-inject /tmp/ol87-azure.ks \
  --extra-args "inst.ks=file:/ol87-azure.ks console=ttyS0,115200" \
  --graphics none --noautoconsole

echo ">> Waiting for install to finish (VM will shut down when done)..."
while sudo virsh domstate ol87 2>/dev/null | grep -q running; do
  sleep 20
  printf '.'
done
echo ""
echo ">> Install finished. Verifying STANDARD partition layout (expect sda1/2/3, NO LVM):"
sudo virt-filesystems -a "$QCOW" --long --parts --filesystems

echo "Base OS installed. Run 04-azure-prep.sh next."
