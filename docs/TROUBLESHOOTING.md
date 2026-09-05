# Troubleshooting: symptom → cause → fix

All of these surfaced during a real build. The Azure error is almost always the
generic `OSProvisioningTimedOut`; the **serial console** (boot diagnostics, or
booting the qcow2 on the builder with `-serial file:...`) is what reveals the
true cause.

---

### `OS Provisioning ... did not finish in the allotted time`
Generic timeout. The VM may even show `VM running` with `VMAgent: Not Ready`.
Root cause is one of the items below. **Read the serial console** — do not guess.

---

### `dracut-initqueue timeout - starting timeout scripts` / `Stopped target Initrd Root Device`
initramfs cannot find/assemble the root disk on Hyper-V.
- Cause: initramfs built hostonly under QEMU (virtio assumptions) and/or LVM.
- Fix: `dracut --no-hostonly --regenerate-all --force --add-drivers "hv_vmbus hv_netvsc hv_storvsc hv_utils"`; install with **standard partitions**.

Verify:
```bash
lsinitrd /boot/initramfs-$(uname -r).img | grep -E 'hv_storvsc|hv_netvsc|hv_vmbus'
```

---

### Every service fails: `Failed at step EXEC ... Permission denied` / AVC `unlabeled_t`
SELinux enforcing on a filesystem whose labels were wiped by offline edits.
- Cause: libguestfs/virt-customize edits leave files `unlabeled_t`.
- Fix: `SELINUX=permissive` in `/etc/selinux/config` + `touch /.autorelabel`.
- Harden later with `scripts/harden-selinux-enforcing.sh`.

---

### `Provisioning failed: cloud-init appears to be installed and enabled, this is not expected, cannot continue`
- Cause: `Provisioning.Agent=waagent` but cloud-init services are enabled.
- Fix: `systemctl disable && systemctl mask cloud-init cloud-init-local cloud-config cloud-final`.

---

### waagent loops on `/proc/net/route contains no routes` / `No route to 168.63.129.16` / `DHCP request timed out`
The primary NIC never got an address.
- Cause: `net.ifnames=0` renames the NIC to `eth0`, but only `ifcfg-enpXsY` exists.
- Fix: write `ifcfg-eth0` (BOOTPROTO=dhcp, ONBOOT=yes), remove `ifcfg-enp*`.
- On the builder KVM you will still see `Error mounting dvd` and wireserver
  DHCP timeouts — those are **KVM-only** artifacts; on real Azure the
  provisioning DVD and wireserver route exist.

---

### `KeyBasedAuthenticationNotPermitted` when using `az storage`
Tenant disables storage account keys.
- Fix: upload straight to a **managed disk** in Upload mode (no storage account)
  as in `05-convert-upload.sh`, or add `--auth-mode login` with the
  *Storage Blob Data Contributor* role.

---

### `az disk grant-access` returns an empty SAS
- Cause: the field name differs by CLI version, or the disk is stuck in
  `ActiveUpload`.
- Fix: try `--query accessSAS` **and** `--query accessSas`. If `ActiveUpload`,
  `az disk revoke-access` then grant again.

---

### `(InvalidVhd) ... cookie value ... is not 'conectix'`
The uploaded blob is not a valid fixed VHD (often an empty/failed upload).
- Fix: ensure the VHD footer is `conectix`
  (`tail -c 512 file.vhd | head -c 8`), 1 MB-aligned, uploaded as **PageBlob**,
  and that azcopy reported `Final Job Status: Completed` before `revoke-access`.

---

### `PropertyChangeNotAllowed ... osDiskImage.source.id` on `image-version create`
- Cause: that image version already exists (partial run).
- Fix: delete it (`az sig image-version delete ... --gallery-image-version X`)
  or use a new version number.

---

### `SkuNotAvailable ... Capacity Restrictions` on VM create
- Cause: region/subscription has no capacity for that size.
- Fix: try another size or region. `01-create-builder.sh` probes several
  nested-virt sizes automatically.

---

### `--os-snapshot` says `Source was not found ... /snapshots/<name>`
- Cause: you passed a **managed disk** name where a snapshot was expected.
- Fix: pass the disk’s **full resource ID** (`az disk show ... --query id -o tsv`).
