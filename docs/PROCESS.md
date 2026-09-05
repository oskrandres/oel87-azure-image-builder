# Process walkthrough

This is the narrative behind the scripts — the *why*, and the alternatives.

## 0. Pick where to build

| Host | Guest OL 8.7 | Notes |
|------|--------------|-------|
| Windows-ARM / Apple Silicon | ❌ native | x86 only via slow QEMU emulation |
| macOS Apple Silicon + QEMU (TCG) | ✅ (slow) | fine for a one-off, ~1–3 h install |
| Windows x86_64 + Hyper-V | ✅ fast | manual Anaconda, `Convert-VHD` |
| **Azure VM + nested KVM** | ✅ fast | **recommended** — scriptable, native speed |

This repo uses the last option.

## 1. Nested-virt builder

`Standard_D4s_v3` (or Dsv3/Dv5/Fsv2) exposes VT-x. Confirm inside the VM:
```bash
egrep -c '(vmx|svm)' /proc/cpuinfo   # > 0
kvm-ok                               # "KVM acceleration can be used"
```
Capacity varies by region; `01-create-builder.sh` retries several sizes.

## 2. Tools + ISO

KVM stack + libguestfs + azcopy. The OL 8.7 DVD ISO lives at a **public**,
login-free mirror:
```
https://yum.oracle.com/ISOS/OracleLinux/OL8/u7/x86_64/OracleLinux-R8-U7-x86_64-dvd.iso
```
`yum.oracle.com` throttles single connections (~3 MB/s); `aria2c -x16` pulls it
in ~2 minutes. Oracle does **not** publish a per-ISO `.sha256` at that path; the
DVD is bootable-verified via `file` and (optionally) Oracle’s GPG process.

## 3. Kickstart install

Unattended, **standard partitions**, no LVM, no swap, Gen2/UEFI, serial console:
```
part /boot/efi --fstype=efi --size=600
part /boot --fstype=xfs --size=1024
part / --fstype=xfs --grow
```
We keep the kickstart `%post` minimal — the OL DVD ships two kernels
(RHCK 4.18 + UEK 5.15) and doing dracut/waagent edits in `%post` hit wrong-KVER
and “waagent.conf not present yet” problems. All heavy prep is done offline next.

## 4. Offline Azure prep (`virt-customize` / `virt-sysprep`)

Doing this **offline** (no boot) is reliable and idempotent. It applies the five
fixes (see README) plus prereqs, then generalizes. Verify before uploading:
```bash
virt-cat  -a ol87.qcow2 /etc/selinux/config | grep SELINUX=      # permissive
virt-ls   -a ol87.qcow2 /etc/sysconfig/network-scripts | grep ifcfg   # ifcfg-eth0
```
You can also **boot the qcow2 on the builder** with a serial log to watch it:
```bash
qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp 2 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file=/tmp/vars.fd \
  -drive file=ol87.qcow2,if=none,id=d0,format=qcow2 \
  -device virtio-scsi-pci -device scsi-hd,drive=d0 \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -nographic -serial file:/tmp/serial.log
```
On KVM you’ll see `Primary interface is [eth0]` (good) plus a couple of
**KVM-only** errors (no provisioning DVD, wireserver DHCP timeout) that do **not**
occur on real Azure.

## 5. Convert + upload + publish

Azure requires a **fixed** VHD with a size **aligned to 1 MB**. Convert via raw:
```bash
qemu-img convert -f qcow2 -O raw ol87.qcow2 ol87.raw
# round up to 1MB, then:
qemu-img convert -f raw -o subformat=fixed,force_size -O vpc ol87.raw ol87.vhd
```
Upload straight to a **managed disk in Upload mode** (works even when the tenant
disables storage-account keys), then publish a gallery image version.

## 6. Validate

Deploy a VM and confirm `Provisioning succeeded`, `eth0` has an IP, swap is on
`/mnt/resource`, waagent is active, and the WebLogic prereqs are present.

## 7. Next: install FLEXCUBE / WebLogic

The image ships the OS prerequisites and the `oracle` user, groups, limits, and
`/u01`. Install WebLogic (silent/response file) and FLEXCUBE on top — either
baked into a new image version (“thick” golden image) or via automation at
deploy time (“thin” image). For banking, a thin base + automated middleware
install is the common pattern.
