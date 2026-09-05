#!/usr/bin/env bash
# =============================================================================
# 04-azure-prep.sh   (run ON the builder VM, as azureuser)
# Offline preparation of the qcow2 for Azure using virt-customize.
#
# This script encodes EVERY fix we found the hard way. Each block maps to a
# real failure we debugged. Do not remove blocks unless you know why.
#
#  (1) initramfs: regenerate ALL kernels, generic (--no-hostonly) + Hyper-V
#      drivers. Fixes 'dracut-initqueue timeout' (can't find root disk) when
#      booting on Azure/Hyper-V. Standard partitions already avoid the LVM
#      variant of this bug.
#  (2) waagent provisioning mode = waagent (self-contained). cloud-init on
#      a stock OL ISO has NO Azure datasource configured, so 'auto' stalls.
#  (3) DISABLE/MASK cloud-init: waagent refuses to provision if cloud-init is
#      enabled ('cloud-init appears to be installed and enabled...').
#  (4) Network: create ifcfg-eth0 (DHCP). With net.ifnames=0 the NIC is eth0,
#      but the installer only wrote ifcfg-enpXsY -> eth0 never comes up ->
#      no route to wireserver -> provisioning times out.
#  (5) SELinux permissive + relabel: offline libguestfs edits leave files
#      'unlabeled_t'; enforcing then blocks ALL exec (every service incl.
#      waagent fails with Permission denied). Permissive lets the VM boot and
#      provision; harden to enforcing after first boot.
#  Plus: udf/vfat modules (Azure passes provisioning config on a UDF dvd),
#        swap on the temporary resource disk (never on the OS disk),
#        WebLogic/FLEXCUBE prereqs, oracle user/groups/limits/sysctl.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-config.sh"

echo ">> (1) initramfs: hv drivers for ALL kernels (generic)"
sudo virt-customize -a "$QCOW" \
  --run-command 'for k in $(ls /lib/modules); do depmod -a "$k"; done' \
  --run-command "dracut --no-hostonly --regenerate-all --force --add-drivers 'hv_vmbus hv_netvsc hv_storvsc hv_utils'" \
  --run-command "printf 'udf\nvfat\n' > /etc/modules-load.d/azure.conf"

echo ">> (2) waagent provisioning + swap on resource disk"
sudo virt-customize -a "$QCOW" \
  --run-command "sed -i 's/^Provisioning.Agent=.*/Provisioning.Agent=waagent/' /etc/waagent.conf" \
  --run-command "sed -i 's/^ResourceDisk.Format=.*/ResourceDisk.Format=y/;s/^ResourceDisk.EnableSwap=.*/ResourceDisk.EnableSwap=y/;s/^ResourceDisk.SwapSizeMB=.*/ResourceDisk.SwapSizeMB=4096/' /etc/waagent.conf"

echo ">> (3) disable + mask cloud-init (conflicts with waagent provisioning)"
sudo virt-customize -a "$QCOW" \
  --run-command "systemctl disable cloud-init cloud-init-local cloud-config cloud-final 2>/dev/null || true" \
  --run-command "systemctl mask cloud-init cloud-init-local cloud-config cloud-final 2>/dev/null || true"

echo ">> (4) network: ifcfg-eth0 DHCP (net.ifnames=0 -> primary NIC is eth0)"
sudo virt-customize -a "$QCOW" \
  --write "/etc/sysconfig/network-scripts/ifcfg-eth0:DEVICE=eth0
NAME=eth0
BOOTPROTO=dhcp
ONBOOT=yes
TYPE=Ethernet
USERCTL=no
PEERDNS=yes
IPV6INIT=no
NM_CONTROLLED=yes" \
  --run-command "rm -f /etc/sysconfig/network-scripts/ifcfg-enp* 2>/dev/null || true" \
  --run-command "echo NETWORKING=yes > /etc/sysconfig/network" \
  --run-command "systemctl enable waagent sshd NetworkManager"

echo ">> (WebLogic/FLEXCUBE prereqs + oracle user/groups/limits/sysctl)"
sudo virt-customize -a "$QCOW" --network \
  --install "$(echo "$WLS_PKGS" | tr ' ' ',')"
sudo virt-customize -a "$QCOW" \
  --run-command "groupadd -g 54321 oinstall 2>/dev/null || true; groupadd -g 54322 dba 2>/dev/null || true; useradd -u 54321 -g oinstall -G dba oracle 2>/dev/null || true" \
  --run-command "mkdir -p /u01/app/oracle /u01/app/oraInventory && chown -R oracle:oinstall /u01 && chmod -R 775 /u01" \
  --append-line "/etc/security/limits.conf:oracle soft nofile 65536" \
  --append-line "/etc/security/limits.conf:oracle hard nofile 65536" \
  --append-line "/etc/security/limits.conf:oracle soft nproc 16384" \
  --append-line "/etc/security/limits.conf:oracle hard nproc 16384" \
  --append-line "/etc/security/limits.conf:oracle soft stack 10240" \
  --write "/etc/sysctl.d/97-oracle.conf:fs.file-max = 6815744
net.ipv4.ip_local_port_range = 9000 65500"

echo ">> (5) SELinux permissive + autorelabel on first boot"
sudo virt-customize -a "$QCOW" \
  --run-command "sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config" \
  --run-command "touch /.autorelabel"

echo ">> Generalize (waagent state + machine identity) with virt-sysprep"
# NOTE: do NOT run 'waagent -deprovision' inside virt-customize/sysprep; it can
# hang waiting on network in the appliance. virt-sysprep's default operations
# (machine-id, ssh hostkeys, logs, udev net rules) generalize correctly.
sudo virt-sysprep -a "$QCOW" --operations defaults \
  --run-command "rm -rf /var/lib/waagent/* 2>/dev/null || true" \
  --run-command "rm -f /var/log/waagent* /root/.bash_history 2>/dev/null || true"

echo "Azure preparation complete. Run 05-convert-upload.sh next."
