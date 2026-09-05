# =============================================================================
# Kickstart: Oracle Linux 8.7 x86_64 -> Azure-ready image
# Standard partitions (NO LVM), NO swap on OS disk, Gen2/UEFI, serial console.
# Used non-interactively by virt-install. See scripts/03-install-ol87.sh
# =============================================================================
text
lang en_US.UTF-8
keyboard us
timezone UTC --utc
network --bootproto=dhcp --device=link --activate --onboot=on
firstboot --disable
# NOTE: SELinux is set to permissive here on purpose. Offline image edits
# (dracut/waagent/network) via libguestfs leave files unlabeled; enforcing
# would block ALL exec on first boot. Harden to enforcing AFTER first boot
# (touch /.autorelabel && reboot, then SELINUX=enforcing).
selinux --permissive
firewall --enabled --service=ssh
services --enabled=sshd,waagent,NetworkManager
bootloader --location=mbr --timeout=1 --append="console=ttyS0,115200n8 earlyprintk=ttyS0 rootdelay=300 net.ifnames=0"

# --- STANDARD partitions, NO LVM, NO swap ------------------------------------
clearpart --all --initlabel
part /boot/efi --fstype=efi --size=600
part /boot --fstype=xfs --size=1024
part / --fstype=xfs --grow

rootpw --plaintext ChangeMe#Root2026
reboot

%packages
@^server-product-environment
WALinuxAgent
cloud-init
cloud-utils-growpart
gdisk
hyperv-daemons
-plymouth
%end

# NOTE: The %post here is intentionally minimal. The heavy Azure preparation
# (initramfs regen with Hyper-V drivers, waagent provisioning mode, cloud-init
# disable, eth0 config, prereqs) is done OFFLINE by scripts/04-azure-prep.sh
# with virt-customize, because doing it in %post proved unreliable (wrong KVER,
# waagent.conf not present yet). Keeping %post minimal avoids those pitfalls.
%post --log=/root/ks-post.log
echo "Kickstart base install complete. Run scripts/04-azure-prep.sh next."
%end
