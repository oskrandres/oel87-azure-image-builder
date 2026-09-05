<#
=============================================================================
 01-create-vm.ps1  — Windows + Hyper-V (run in an ELEVATED PowerShell)
 Creates a Gen2 (UEFI) Hyper-V VM and boots the Oracle Linux 8.7 ISO so you
 can install the OS by hand in Anaconda.

 Requires: Windows 10/11 Pro/Enterprise x86_64 with Hyper-V enabled.
   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All
=============================================================================
#>

# ---- Parameters (edit these) ------------------------------------------------
$VMName   = "ol87-build"
$Root     = "F:\oel87"                                        # working folder
$IsoPath  = "F:\oel87\OracleLinux-R8-U7-x86_64-dvd.iso"       # download first
$DiskGB   = 64
$MemoryGB = 6
$Switch   = "Default Switch"                                  # or your external vSwitch

# ---- Build ------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $Root | Out-Null

# Dynamic VHDX for the install (converted to a FIXED VHD later for Azure)
$Vhdx = Join-Path $Root "$VMName.vhdx"
New-VHD -Path $Vhdx -SizeBytes ($DiskGB * 1GB) -Dynamic | Out-Null

New-VM -Name $VMName -Generation 2 -MemoryStartupBytes ($MemoryGB * 1GB) `
  -VHDPath $Vhdx -SwitchName $Switch | Out-Null
Set-VM -Name $VMName -ProcessorCount 4

Add-VMDvdDrive -VMName $VMName -Path $IsoPath
$dvd = Get-VMDvdDrive -VMName $VMName

# CRITICAL for Linux on Gen2: disable Secure Boot, boot from DVD first
Set-VMFirmware -VMName $VMName -FirstBootDevice $dvd -EnableSecureBoot Off

Start-VM -Name $VMName
Write-Host "VM '$VMName' started. Opening console..." -ForegroundColor Green
Write-Host "In Anaconda choose: Standard Partition (NO LVM), XFS, NO swap." -ForegroundColor Yellow
Write-Host "Layout: /boot/efi 600M (EFI), /boot 1G xfs, / rest xfs. Software: 'Server'." -ForegroundColor Yellow
vmconnect.exe localhost $VMName
