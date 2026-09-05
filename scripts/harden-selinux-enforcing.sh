#!/usr/bin/env bash
# =============================================================================
# harden-selinux-enforcing.sh   (run INSIDE a deployed VM, as root)
# The image ships SELinux=permissive (required so offline-edited files boot).
# Run this once on a running VM to relabel and switch to enforcing.
# The VM will REBOOT to complete the relabel.
# =============================================================================
set -euo pipefail
echo ">> Forcing full filesystem relabel on next boot"
touch /.autorelabel
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
echo ">> Rebooting to relabel + enter enforcing mode..."
reboot
