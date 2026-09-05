#!/usr/bin/env bash
# =============================================================================
# 02-setup-builder.sh   (run ON the builder VM, as azureuser)
# Installs KVM/libvirt/qemu + azcopy + tools, and downloads the OEL 8.7 ISO.
#
# Uses aria2 for the ISO: yum.oracle.com throttles single connections to
# ~3 MB/s; aria2 -x16 pulls ~100 MB/s (11 GB in ~2 min).
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-config.sh"

echo ">> Verify nested virtualization is present"
if [ "$(egrep -c '(vmx|svm)' /proc/cpuinfo)" -eq 0 ]; then
  echo "ERROR: no VT-x/SVM. This VM size does not expose nested virt."; exit 1
fi

echo ">> Install KVM stack + tools"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  qemu-kvm libvirt-daemon-system libvirt-clients virtinst \
  qemu-utils genisoimage libguestfs-tools aria2 >/dev/null
sudo systemctl enable --now libvirtd
sudo kvm-ok || true

echo ">> Install azcopy"
cd /tmp
wget -q -O azcopy.tar.gz https://aka.ms/downloadazcopy-v10-linux
tar -xf azcopy.tar.gz
sudo cp azcopy_linux*/azcopy /usr/local/bin/ && sudo chmod +x /usr/local/bin/azcopy
azcopy --version

echo ">> Download Oracle Linux 8.7 ISO (fast, multi-connection)"
sudo mkdir -p "$WORKDIR"; sudo chmod 777 "$WORKDIR"
cd "$WORKDIR"
aria2c -x16 -s16 -k1M --file-allocation=none -o OL87.iso "$OL_ISO_URL"

echo ">> Verify ISO is bootable"
file "$WORKDIR/OL87.iso" | grep -q "ISO 9660" && echo "ISO OK" || { echo "ISO invalid"; exit 1; }
echo "Builder setup complete."
