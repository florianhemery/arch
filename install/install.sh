#!/usr/bin/env bash
# Arch Linux automated installer - dual-boot with Windows
# Run from Arch ISO live environment as root

set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH_PROJECT_ROOT="${ARCH_PROJECT_ROOT:-$(cd "$INSTALL_DIR/.." && pwd)}"
export ARCH_PROJECT_ROOT

# shellcheck source=lib/common.sh
source "$INSTALL_DIR/lib/common.sh"
# shellcheck source=lib/disk.sh
source "$INSTALL_DIR/lib/disk.sh"
# shellcheck source=lib/packages.sh
source "$INSTALL_DIR/lib/packages.sh"
# shellcheck source=lib/bootloader.sh
source "$INSTALL_DIR/lib/bootloader.sh"
# shellcheck source=lib/users.sh
source "$INSTALL_DIR/lib/users.sh"

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --dry-run           Simulate without making changes
  --disk DISK         Target disk (e.g. nvme0n1), auto-detected from report
  --root-gib SIZE     Root partition size in GiB (default: from report)
  --user USERNAME     Primary user (default: archuser)
  --password PASS     User password (prompt if omitted and not dry-run)
  --bootloader TYPE   grub or systemd-boot (default: grub)
  --report PATH       hardware-report.json path
  -h, --help          Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) export DRY_RUN=1; shift ;;
      --disk) TARGET_DISK="$2"; shift 2 ;;
      --root-gib) ROOT_GIB="$2"; shift 2 ;;
      --user) DEFAULT_USER="$2"; shift 2 ;;
      --password) USER_PASSWORD="$2"; shift 2 ;;
      --bootloader) export BOOTLOADER="$2"; shift 2 ;;
      --report) export HARDWARE_REPORT="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) log_error "Option inconnue: $1"; usage; exit 1 ;;
    esac
  done
}

detect_target_disk() {
  if [[ -n "${TARGET_DISK:-}" ]]; then
    echo "$TARGET_DISK"
    return
  fi
  local disk_num
  disk_num=$(json_get 'install.targetDisk' "$HARDWARE_REPORT" 2>/dev/null || echo "")
  if [[ -n "$disk_num" && "$disk_num" != "null" ]]; then
    lsblk -dno NAME | sed -n "$((disk_num + 1))p" 2>/dev/null || lsblk -dno NAME | head -1
  else
    lsblk -dno NAME,TYPE | awk '$2=="disk" {print $1; exit}'
  fi
}

main() {
  parse_args "$@"
  require_root
  validate_hardware_report

  local can_install
  can_install=$(json_get 'install.canInstall' "$HARDWARE_REPORT" 2>/dev/null || echo "true")
  if [[ "$can_install" != "true" && "$can_install" != "True" ]]; then
    local reason
    reason=$(json_get 'install.reason' "$HARDWARE_REPORT" 2>/dev/null || echo "unknown")
    log_error "Installation impossible: $reason"
    exit 1
  fi

  local bl_status
  bl_status=$(json_get 'security.bitlocker.status' "$HARDWARE_REPORT" 2>/dev/null || echo "Unknown")
  case "$bl_status" in
    On)
      log_warn "BitLocker est ACTIF sur Windows : suspendez-le avant d'installer GRUB,"
      log_warn "sinon Windows demandera la clé de récupération au prochain démarrage."
      ;;
    Unknown)
      log_warn "Statut BitLocker inconnu (analyse lancée sans droits admin ?)."
      log_warn "Vérifiez-le sous Windows avant de continuer sur une machine réelle."
      ;;
  esac

  local disk root_gib
  disk=$(detect_target_disk)
  root_gib="${ROOT_GIB:-$(json_get 'install.suggestedRootGiB' "$HARDWARE_REPORT" 2>/dev/null || echo 250)}"
  export BOOTLOADER="${BOOTLOADER:-grub}"

  if [[ "$BOOTLOADER" == "systemd-boot" ]]; then
    log_error "systemd-boot non supporté : le noyau est sur btrfs (/boot), pas sur l'ESP Windows."
    log_error "L'ESP existante (~200 Mo) est montée sur /boot/efi ; systemd-boot ne peut pas lire le btrfs."
    log_error "Utilisez --bootloader grub (défaut)."
    exit 1
  fi

  log_info "=== Installation Arch Linux ==="
  log_info "Disque: /dev/$disk | Root: ${root_gib} GiB | Bootloader: $BOOTLOADER"
  log_info "DRY_RUN=$DRY_RUN"

  refresh_mirrors_live

  local part_dev
  part_dev=$(partition_disk "$disk" "$root_gib")
  mount_btrfs_layout "$part_dev" /mnt

  mapfile -t profiles < <(get_profiles_from_report)
  run_pacstrap /mnt "${profiles[@]}"

  enable_multilib_chroot /mnt
  configure_zram_chroot /mnt

  generate_fstab /mnt
  configure_locale_chroot /mnt "$(json_get 'locale.timezone' "$HARDWARE_REPORT" 2>/dev/null | tr ' ' '_' || echo 'Europe/Paris')" "fr"

  if [[ -z "${USER_PASSWORD:-}" ]] && ! is_dry_run; then
    read -rsp "Mot de passe pour $DEFAULT_USER: " USER_PASSWORD
    echo
  fi
  create_user /mnt "$DEFAULT_USER" "${USER_PASSWORD:-}"
  enable_services_chroot /mnt
  setup_bootloader /mnt "$disk"

  # Copy project for post-install configuration
  if ! is_dry_run; then
    mkdir -p "/mnt/home/$DEFAULT_USER/arch-setup/analyze"
    cp -r "$ARCH_PROJECT_ROOT/configure" "$ARCH_PROJECT_ROOT/dotfiles" "/mnt/home/$DEFAULT_USER/arch-setup/"
    cp "$ARCH_PROJECT_ROOT/arch-setup" "/mnt/home/$DEFAULT_USER/arch-setup/"
    chmod +x "/mnt/home/$DEFAULT_USER/arch-setup/arch-setup"
    cp "$HARDWARE_REPORT" "/mnt/home/$DEFAULT_USER/arch-setup/analyze/hardware-report.json"
    mkdir -p "/mnt/home/$DEFAULT_USER/arch-setup/packages"
    cp -r "$ARCH_PROJECT_ROOT/install/packages/" "/mnt/home/$DEFAULT_USER/arch-setup/packages/"
    chown -R "$DEFAULT_USER:$DEFAULT_USER" "/mnt/home/$DEFAULT_USER/arch-setup"
  else
    log_info "[DRY-RUN] Copie arch-setup, configure/, dotfiles/, packages/ et hardware-report.json"
  fi

  log_info "=== Installation terminée ==="
  if is_dry_run; then
    log_info "[DRY-RUN] Après reboot : ~/arch-setup/arch-setup first-boot"
  else
    log_info "Redémarrez, connectez-vous, puis : ~/arch-setup/arch-setup first-boot"
  fi
}

main "$@"
