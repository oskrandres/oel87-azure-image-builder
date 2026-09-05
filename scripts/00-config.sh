#!/usr/bin/env bash
# =============================================================================
# 00-config.sh - Shared configuration. Source this from every script:
#   source ./00-config.sh
# Override any value via environment variables before running.
# =============================================================================
set -euo pipefail

# ---- Azure ------------------------------------------------------------------
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-<YOUR_SUBSCRIPTION_ID>}"
export LOCATION="${LOCATION:-westus2}"                 # region WITH nested-virt capacity
export RG="${RG:-rg-oel-build}"                        # resource group for build assets
export BUILDER_VM="${BUILDER_VM:-oel-builder}"         # nested-virt build host (Ubuntu)
export BUILDER_SIZE="${BUILDER_SIZE:-Standard_D4s_v3}" # Dv3/Dsv3/Dv5/Fsv2 support nested virt
export BUILDER_ADMIN="${BUILDER_ADMIN:-azureuser}"

# ---- Image / gallery --------------------------------------------------------
export GALLERY="${GALLERY:-FlexcubeGallery}"
export IMAGE_DEF="${IMAGE_DEF:-OEL87-Flexcube}"
export IMAGE_VERSION="${IMAGE_VERSION:-1.0.0}"
export IMAGE_PUBLISHER="${IMAGE_PUBLISHER:-MyOrg}"
export IMAGE_OFFER="${IMAGE_OFFER:-OracleLinux}"
export IMAGE_SKU="${IMAGE_SKU:-8.7}"
export OSDISK_NAME="${OSDISK_NAME:-ol87-osdisk}"

# ---- Guest OS build (on the builder) ----------------------------------------
export OL_ISO_URL="${OL_ISO_URL:-https://yum.oracle.com/ISOS/OracleLinux/OL8/u7/x86_64/OracleLinux-R8-U7-x86_64-dvd.iso}"
export WORKDIR="${WORKDIR:-/var/lib/libvirt/images}"
export QCOW="${QCOW:-$WORKDIR/ol87.qcow2}"
export VHD="${VHD:-$WORKDIR/ol87.vhd}"
export DISK_GB="${DISK_GB:-64}"

# ---- WebLogic / FLEXCUBE prereqs (edit to taste) ----------------------------
export WLS_PKGS="${WLS_PKGS:-binutils gcc gcc-c++ glibc glibc-devel glibc-langpack-en libaio libaio-devel libnsl libnsl2 libstdc++ libstdc++-devel make sysstat unzip tar which ksh xorg-x11-xauth java-1.8.0-openjdk-devel}"

echo "[config] RG=$RG LOCATION=$LOCATION IMAGE=$GALLERY/$IMAGE_DEF/$IMAGE_VERSION"
