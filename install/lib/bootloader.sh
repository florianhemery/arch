#!/usr/bin/env bash
# Bootloader configuration for dual-boot UEFI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=disk.sh
source "$SCRIPT_DIR/disk.sh"

mount_efi_partition() {
  local disk="$1"
  local target="${2:-/mnt}"
  local efi_part
  efi_part=$(find_efi_partition "$disk")
  [[ -n "$efi_part" ]] || { log_error "Partition EFI introuvable sur /dev/$disk"; return 1; }
  local efi_dev="/dev/$efi_part"
  if is_dry_run; then
    log_info "[DRY-RUN] mount $efi_dev $target/boot/efi"
    echo "$efi_dev"
    return 0
  fi
  mkdir -p "$target/boot/efi"
  mount "$efi_dev" "$target/boot/efi"
  echo "$efi_dev"
}

install_grub_dualboot() {
  local target="${1:-/mnt}"
  local disk="$2"
  log_info "Installation GRUB dual-boot sur /dev/$disk"
  if is_dry_run; then
    log_info "[DRY-RUN] grub-install --target=x86_64-efi --efi-directory=$target/boot/efi --bootloader-id=Arch"
    log_info "[DRY-RUN] os-prober pour entrée Windows"
    return 0
  fi
  arch-chroot "$target" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Arch --recheck
  sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' "$target/etc/default/grub" 2>/dev/null || \
    echo 'GRUB_DISABLE_OS_PROBER=false' >> "$target/etc/default/grub"
  arch-chroot "$target" grub-mkconfig -o /boot/grub/grub.cfg
}

install_systemd_boot() {
  local target="${1:-/mnt}"
  local root_uuid
  root_uuid=$(blkid -s UUID -o value "$(findmnt -no SOURCE "$target")")
  if is_dry_run; then
    log_info "[DRY-RUN] systemd-boot avec root UUID=$root_uuid"
    return 0
  fi
  arch-chroot "$target" bootctl install
  mkdir -p "$target/boot/loader/entries"
  cat > "$target/boot/loader/loader.conf" <<EOF
default arch.conf
timeout 3
editor  no
EOF
  cat > "$target/boot/loader/entries/arch.conf" <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=$root_uuid rw rootflags=subvol=@ quiet
EOF
}

setup_bootloader() {
  local target="${1:-/mnt}"
  local disk="$2"
  local bootloader="${BOOTLOADER:-grub}"
  mount_efi_partition "$disk" "$target"
  case "$bootloader" in
    grub) install_grub_dualboot "$target" "$disk" ;;
    systemd-boot) install_systemd_boot "$target" ;;
    *) log_error "Bootloader inconnu: $bootloader"; return 1 ;;
  esac
}
