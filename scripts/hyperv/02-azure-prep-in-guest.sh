#!/usr/bin/env bash
# =============================================================================
# 02-azure-prep-in-guest.sh   (run INSIDE the Oracle Linux guest, as root)
#
# Hyper-V build has NO virt-customize, so all Azure preparation is done here,
# inside the running guest, AFTER installing the OS. Applying changes in the
# running system means SELinux contexts are set correctly (unlike offline
# libguestfs edits), so you can KEEP SELinux enforcing.
#
# This encodes the same fixes proven to make an OL image provision on Azure:
#   (1) initramfs with Hyper-V drivers (regenerate)
#   (2) waagent provisioning + swap on the temporary resource disk
#   (3) disable/mask cloud-init (conflicts with waagent provisioning)
#   (4) ifcfg-eth0 (DHCP)  — net.ifnames=0 makes the NIC 'eth0'
#   (5) GRUB serial console + net.ifnames=0
#   + udf/vfat modules, WebLogic/FLEXCUBE prereqs, oracle user/limits/sysctl
#
# Run it, verify, then run 03 to generalize + convert.  Do NOT reboot after
# generalizing.
# =============================================================================
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }
KVER=$(uname -r)

echo ">> (5) GRUB: serial console + predictable NIC name"
sed -i 's/^\(GRUB_CMDLINE_LINUX="[^"]*\)"/\1 console=ttyS0,115200n8 earlyprintk=ttyS0 rootdelay=300 net.ifnames=0"/' /etc/default/grub
sed -i 's/\brhgb\b//g; s/\bquiet\b//g' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
[ -f /boot/efi/EFI/redhat/grub.cfg ] && grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg || true

echo ">> (1) initramfs with Hyper-V drivers"
cp /boot/initramfs-$KVER.img /boot/initramfs-$KVER.img.bak
dracut --force --add-drivers "hv_vmbus hv_netvsc hv_storvsc hv_utils" /boot/initramfs-$KVER.img $KVER
printf 'udf\nvfat\n' > /etc/modules-load.d/azure.conf

echo ">> Install WALinuxAgent + cloud-init + Hyper-V daemons"
dnf install -y WALinuxAgent cloud-init cloud-utils-growpart gdisk hyperv-daemons

echo ">> (2) waagent provisioning + swap on resource disk"
sed -i 's/^Provisioning.Agent=.*/Provisioning.Agent=waagent/' /etc/waagent.conf
sed -i 's/^ResourceDisk.Format=.*/ResourceDisk.Format=y/' /etc/waagent.conf
sed -i 's/^ResourceDisk.EnableSwap=.*/ResourceDisk.EnableSwap=y/' /etc/waagent.conf
sed -i 's/^ResourceDisk.SwapSizeMB=.*/ResourceDisk.SwapSizeMB=4096/' /etc/waagent.conf

echo ">> (3) disable + mask cloud-init"
systemctl disable cloud-init cloud-init-local cloud-config cloud-final 2>/dev/null || true
systemctl mask    cloud-init cloud-init-local cloud-config cloud-final 2>/dev/null || true

echo ">> (4) network: ifcfg-eth0 (DHCP)"
cat >/etc/sysconfig/network-scripts/ifcfg-eth0 <<'EOF'
DEVICE=eth0
NAME=eth0
BOOTPROTO=dhcp
ONBOOT=yes
TYPE=Ethernet
USERCTL=no
PEERDNS=yes
IPV6INIT=no
NM_CONTROLLED=yes
EOF
rm -f /etc/sysconfig/network-scripts/ifcfg-enp* 2>/dev/null || true
echo NETWORKING=yes > /etc/sysconfig/network

echo ">> Enable services; remove machine-specific net rules"
systemctl enable waagent sshd NetworkManager
rm -f /etc/udev/rules.d/70-persistent-net.rules

echo ">> WebLogic/FLEXCUBE prereqs + oracle user/groups/limits/sysctl"
dnf install -y binutils gcc gcc-c++ glibc glibc-devel glibc-langpack-en \
  libaio libaio-devel libnsl libnsl2 libstdc++ libstdc++-devel \
  make sysstat unzip tar which ksh xorg-x11-xauth java-1.8.0-openjdk-devel
cat >>/etc/security/limits.conf <<'EOF'
oracle soft nofile 65536
oracle hard nofile 65536
oracle soft nproc 16384
oracle hard nproc 16384
oracle soft stack 10240
EOF
cat >/etc/sysctl.d/97-oracle.conf <<'EOF'
fs.file-max = 6815744
net.ipv4.ip_local_port_range = 9000 65500
EOF
sysctl --system >/dev/null
groupadd -g 54321 oinstall 2>/dev/null || true
groupadd -g 54322 dba 2>/dev/null || true
useradd -u 54321 -g oinstall -G dba oracle 2>/dev/null || true
mkdir -p /u01/app/oracle /u01/app/oraInventory
chown -R oracle:oinstall /u01 && chmod -R 775 /u01

echo ""
echo ">> VERIFY (all three must look right) ============================"
echo "-- initramfs hv drivers:"
lsinitrd /boot/initramfs-$KVER.img | grep -oE 'hv_(vmbus|storvsc|netvsc)' | sort -u
echo "-- services:"
systemctl is-enabled waagent sshd NetworkManager
echo "-- cloud-init (should be masked):"
systemctl is-enabled cloud-init 2>&1 || true
echo "================================================================="
echo "If OK, run 03-generalize.sh (LAST in-guest step)."
