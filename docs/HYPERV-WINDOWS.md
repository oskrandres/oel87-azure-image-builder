# Building the image on Windows + Hyper-V (manual)

This is the **Hyper-V** path, for building the Oracle Linux 8.7 image by hand on
a local **Windows** machine. It produces the same Azure-ready image as the
KVM/Azure-builder path, but the mechanics differ:

- The OS is installed **by hand in Anaconda** (no kickstart automation needed,
  though you may still use the ISO’s kickstart support).
- There is **no `virt-customize`** on Windows, so all Azure preparation is done
  **inside the running guest** (`scripts/hyperv/02-azure-prep-in-guest.sh`).
- The disk is converted with **`Convert-VHD`** and uploaded with **`Add-AzVhd`**.

> Because the fixes are applied **inside a running system** (not offline via
> libguestfs), SELinux contexts are set correctly — so on Hyper-V you can
> **keep SELinux `enforcing`** (the permissive workaround from the offline flow
> is not required here). `03-generalize.sh` still runs `touch /.autorelabel` as
> a safety net.

## Requirements

- Windows 10/11 **Pro/Enterprise x86_64** (Hyper-V is not on ARM or Home).
- Hyper-V enabled:
  ```powershell
  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All
  ```
- ~80 GB free. The OL 8.7 DVD ISO downloaded to e.g. `F:\oel87\`.
- `Az` PowerShell module for the upload: `Install-Module Az -Scope CurrentUser`.

## Steps

### 0) Download the ISO
```powershell
New-Item -ItemType Directory -Force -Path F:\oel87 | Out-Null
curl.exe -L -C - -o F:\oel87\OracleLinux-R8-U7-x86_64-dvd.iso `
  "https://yum.oracle.com/ISOS/OracleLinux/OL8/u7/x86_64/OracleLinux-R8-U7-x86_64-dvd.iso"
```

### 1) Create the Gen2 VM and install OL 8.7
Edit the paths at the top of `scripts/hyperv/01-create-vm.ps1`, then run it in an
**elevated** PowerShell:
```powershell
.\scripts\hyperv\01-create-vm.ps1
```
It creates a **Gen2 (UEFI)** VM with **Secure Boot OFF** (required for Linux) and
opens the console. In Anaconda:

- **Installation Destination → Custom → Standard Partition** (NOT LVM):
  - `/boot/efi` — 600 MB — EFI System Partition
  - `/boot` — 1 GB — xfs
  - `/` — remaining — xfs
  - **No swap** (Azure uses the temp disk for swap)
- Software selection: **Server** (no GUI).
- Create a user + password; enable networking (DHCP).

After install completes, remove the DVD and boot from disk:
```powershell
Stop-VM -Name ol87-build -Force
$d = Get-VMDvdDrive -VMName ol87-build
Remove-VMDvdDrive -VMName ol87-build -ControllerNumber $d.ControllerNumber -ControllerLocation $d.ControllerLocation
Start-VM -Name ol87-build
vmconnect.exe localhost ol87-build
```

### 2) Azure preparation (inside the guest, as root)
Copy `scripts/hyperv/02-azure-prep-in-guest.sh` into the VM (or paste it) and run
it as root. It applies the five fixes + prereqs and prints a verification block.
Easiest transfer: enable SSH in the guest and `scp`, or paste via the console.

```bash
sudo bash 02-azure-prep-in-guest.sh
# check the VERIFY block: hv drivers present, services enabled, cloud-init masked
```

### 3) Generalize (last in-guest step)
```bash
sudo bash 03-generalize.sh     # runs waagent -deprovision, then powers off
```
Do **not** boot the VM again in Hyper-V after this.

### 4) Convert + upload + publish (Windows, elevated PowerShell)
Edit the parameters at the top of `scripts/hyperv/04-convert-upload.ps1`
(subscription, RG, region, gallery names), then:
```powershell
Connect-AzAccount
.\scripts\hyperv\04-convert-upload.ps1
```
This converts the VHDX → **fixed VHD**, aligns to 1 MB, uploads via `Add-AzVhd`,
and publishes the gallery image version.

### 5) Deploy + validate
Same as the main flow — deploy a VM from the gallery image and confirm
`Provisioning succeeded`:
```powershell
$img = (Get-AzGalleryImageVersion -ResourceGroupName rg-oel-build `
  -GalleryName FlexcubeGallery -GalleryImageDefinitionName OEL87-Flexcube -Name 1.0.0).Id
New-AzVm -ResourceGroupName rg-oel-build -Name oel-test -Image $img `
  -Size Standard_D2s_v3 -Credential (Get-Credential) -OpenPorts 22
```

## Hyper-V gotchas

- **Secure Boot OFF** on the Gen2 VM, or the Linux ISO won’t boot.
- **Gen2 ↔ V2** everywhere (Hyper-V Gen2 VM → `Add-AzVhd -Generation V2` →
  image definition `-HyperVGeneration V2`).
- Azure needs a **fixed** VHD (not VHDX, not dynamic). `Convert-VHD -VHDType Fixed`.
- The fixed VHD occupies its full size on disk (e.g. 64 GB). Ensure free space.
- If you must re-enter the image after `deprovision`, you’ll have no user — boot
  with GRUB `rd.break` to reset, then re-run generalize. Better: snapshot/export
  the VHDX **before** generalizing.
- **NSG note (deploy):** open port 22 on **both** the NIC NSG **and** the subnet
  NSG if both exist; inbound must pass both. Prefer Azure Bastion in production.

See `docs/TROUBLESHOOTING.md` for symptom → cause → fix (shared with the KVM path).
