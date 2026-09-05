<#
=============================================================================
 04-convert-upload.ps1  — Windows (run in an ELEVATED PowerShell)
 Converts the Hyper-V VHDX to a FIXED VHD (Azure requirement) and uploads it
 to an Azure Compute Gallery.

 Requires: Az PowerShell module (Install-Module Az -Scope CurrentUser), and
   Connect-AzAccount already done.
=============================================================================
#>

# ---- Parameters (edit these) ------------------------------------------------
$VMName        = "ol87-build"
$Root          = "F:\oel87"
$Vhdx          = Join-Path $Root "$VMName.vhdx"
$Vhd           = Join-Path $Root "ol87.vhd"

$SubscriptionId = "<YOUR_SUBSCRIPTION_ID>"
$RG             = "rg-oel-build"
$Location       = "eastus2"
$Gallery        = "FlexcubeGallery"
$ImageDef       = "OEL87-Flexcube"
$ImageVersion   = "1.0.0"
$Publisher      = "MyOrg"
$Offer          = "OracleLinux"
$Sku            = "8.7"
$DiskName       = "ol87-osdisk"

# ---- Convert VHDX (dynamic) -> fixed VHD ------------------------------------
Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
Write-Host ">> Converting VHDX -> fixed VHD (Azure requires FIXED)..." -ForegroundColor Cyan
Convert-VHD -Path $Vhdx -DestinationPath $Vhd -VHDType Fixed

# Azure requires the virtual size aligned to 1 MB. Hyper-V VHDs usually are,
# but align just in case:
$img = Get-VHD -Path $Vhd
$MB = 1MB
$aligned = [math]::Ceiling($img.Size / $MB) * $MB
if ($img.Size -ne $aligned) {
  Write-Host ">> Resizing to 1MB-aligned size..." -ForegroundColor Cyan
  Resize-VHD -Path $Vhd -SizeBytes $aligned
}

# ---- Upload to Azure --------------------------------------------------------
Connect-AzAccount -ErrorAction SilentlyContinue | Out-Null
Set-AzContext -Subscription $SubscriptionId | Out-Null
New-AzResourceGroup -Name $RG -Location $Location -Force | Out-Null

Write-Host ">> Uploading VHD directly to a managed disk (Gen2/V2)..." -ForegroundColor Cyan
# Add-AzVhd streams the VHD straight into a managed disk (sparse upload).
Add-AzVhd -ResourceGroupName $RG -Location $Location `
  -DiskName $DiskName -LocalFilePath $Vhd `
  -Hyperv Generation V2 -DiskOsType Linux -Verbose

# ---- Publish gallery image --------------------------------------------------
Write-Host ">> Publishing gallery image version..." -ForegroundColor Cyan
$gal = Get-AzGallery -ResourceGroupName $RG -Name $Gallery -ErrorAction SilentlyContinue
if (-not $gal) { New-AzGallery -ResourceGroupName $RG -Name $Gallery -Location $Location | Out-Null }

$def = Get-AzGalleryImageDefinition -ResourceGroupName $RG -GalleryName $Gallery -Name $ImageDef -ErrorAction SilentlyContinue
if (-not $def) {
  New-AzGalleryImageDefinition -ResourceGroupName $RG -GalleryName $Gallery `
    -Name $ImageDef -Location $Location -OsState Generalized -OsType Linux `
    -Publisher $Publisher -Offer $Offer -Sku $Sku -HyperVGeneration V2 | Out-Null
}

$disk = Get-AzDisk -ResourceGroupName $RG -DiskName $DiskName
New-AzGalleryImageVersion -ResourceGroupName $RG -GalleryName $Gallery `
  -GalleryImageDefinitionName $ImageDef -Name $ImageVersion -Location $Location `
  -SourceImageId $disk.Id | Out-Null

Write-Host "Published: $Gallery/$ImageDef/$ImageVersion" -ForegroundColor Green
