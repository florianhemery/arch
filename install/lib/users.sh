#!/usr/bin/env bash
# User and locale configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

DEFAULT_USER="${DEFAULT_USER:-archuser}"
DEFAULT_HOSTNAME="${DEFAULT_HOSTNAME:-honor-arch}"

configure_locale_chroot() {
  local target="${1:-/mnt}"
  local timezone="${2:-Europe/Paris}"
  local keymap="${3:-fr}"
  if is_dry_run; then
    log_info "[DRY-RUN] locale-gen, timezone=$timezone, keymap=$keymap"
    return 0
  fi
  echo "LANG=fr_FR.UTF-8" > "$target/etc/locale.conf"
  echo "KEYMAP=$keymap" > "$target/etc/vconsole.conf"
  echo "$DEFAULT_HOSTNAME" > "$target/etc/hostname"
  cat >> "$target/etc/hosts" <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $DEFAULT_HOSTNAME.localdomain $DEFAULT_HOSTNAME
EOF
  sed -i 's/^#fr_FR.UTF-8 UTF-8/fr_FR.UTF-8 UTF-8/' "$target/etc/locale.gen"
  arch-chroot "$target" locale-gen
  arch-chroot "$target" ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
  arch-chroot "$target" hwclock --systohc
}

create_user() {
  local target="${1:-/mnt}"
  local username="${2:-$DEFAULT_USER}"
  local password="${3:-}"
  if is_dry_run; then
    log_info "[DRY-RUN] useradd $username wheel video audio input"
    return 0
  fi
  arch-chroot "$target" useradd -m -G wheel,video,audio,input,storage,power -s /bin/bash "$username" 2>/dev/null || true
  if [[ -n "$password" ]]; then
    echo "$username:$password" | arch-chroot "$target" chpasswd
  fi
  sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "$target/etc/sudoers"
}

enable_services_chroot() {
  local target="${1:-/mnt}"
  local services=(NetworkManager bluetooth sddm pipewire pipewire-pulse wireplumber)
  if is_dry_run; then
    log_info "[DRY-RUN] enable services: ${services[*]}"
    return 0
  fi
  for svc in "${services[@]}"; do
    arch-chroot "$target" systemctl enable "$svc" 2>/dev/null || log_warn "Service $svc non disponible"
  done
}
