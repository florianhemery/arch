#!/usr/bin/env bash
# Post-installation system configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH_SETUP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUR_LIST="${AUR_LIST:-$ARCH_SETUP_ROOT/packages/aur.txt}"
LOG_FILE="${LOG_FILE:-/tmp/arch-configure.log}"
DRY_RUN="${DRY_RUN:-0}"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"; }

is_dry_run() { [[ "$DRY_RUN" == "1" ]]; }

enable_multilib() {
  log "Activation dépôt multilib"
  if is_dry_run; then
    log "[DRY-RUN] décommenter [multilib] dans /etc/pacman.conf"
    return 0
  fi
  if grep -q '^\[multilib\]' /etc/pacman.conf; then
    return 0
  fi
  sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ {
    s/^#\[multilib\]/[multilib]/
    s/^#Include = \/etc\/pacman.d\/mirrorlist/Include = \/etc\/pacman.d\/mirrorlist/
  }' /etc/pacman.conf
  sudo pacman -Sy
}

install_intel_drivers() {
  log "Configuration pilotes Intel (Mesa, Vulkan, media)"
  if is_dry_run; then
    log "[DRY-RUN] pacman -S mesa vulkan-intel intel-media-driver libva-intel-driver"
    return 0
  fi
  enable_multilib
  sudo pacman -S --needed --noconfirm \
    mesa vulkan-intel intel-media-driver libva-intel-driver \
    lib32-mesa lib32-vulkan-intel thermald
  sudo systemctl enable --now thermald
}

configure_pipewire() {
  log "Configuration audio PipeWire"
  if is_dry_run; then return 0; fi
  systemctl --user enable pipewire pipewire-pulse wireplumber 2>/dev/null || true
}

configure_sddm() {
  log "Configuration SDDM comme gestionnaire d'affichage"
  if is_dry_run; then
    log "[DRY-RUN] systemctl enable sddm"
    return 0
  fi
  sudo systemctl enable sddm
  sudo mkdir -p /etc/sddm.conf.d
  sudo tee /etc/sddm.conf.d/autologin.conf > /dev/null <<'EOF'
[Autologin]
# Décommentez pour connexion auto (désactivé par défaut pour sécurité)
# User=archuser
# Session=hyprland.desktop
EOF
}

configure_network() {
  log "Configuration réseau NetworkManager"
  if is_dry_run; then return 0; fi
  sudo systemctl enable --now NetworkManager
  sudo systemctl enable --now bluetooth
}

configure_firewall() {
  log "Configuration pare-feu"
  if is_dry_run; then return 0; fi
  sudo systemctl enable --now firewalld
  sudo firewall-cmd --set-default-zone=public 2>/dev/null || true
}

configure_reflector() {
  log "Activation reflector.timer pour miroirs à jour"
  if is_dry_run; then
    log "[DRY-RUN] systemctl enable reflector.timer"
    return 0
  fi
  sudo systemctl enable --now reflector.timer 2>/dev/null || true
}

configure_snapper() {
  log "Configuration Snapper pour snapshots btrfs"
  if is_dry_run; then
    log "[DRY-RUN] snapper create-config /"
    return 0
  fi
  if ! snapper list-configs 2>/dev/null | grep -q 'root'; then
    sudo snapper -c root create-config / 2>/dev/null || log "Snapper déjà configuré ou btrfs non monté"
  fi
}

install_paru() {
  log "Installation de paru (helper AUR)"
  if is_dry_run; then
    log "[DRY-RUN] makepkg paru depuis AUR"
    return 0
  fi
  if command -v paru &>/dev/null; then
    log "paru déjà installé"
    return 0
  fi
  local tmpdir
  tmpdir=$(mktemp -d)
  git clone https://aur.archlinux.org/paru.git "$tmpdir/paru"
  (cd "$tmpdir/paru" && makepkg -si --noconfirm)
  rm -rf "$tmpdir"
}

install_aur_packages() {
  log "Installation paquets AUR depuis $AUR_LIST"
  if is_dry_run; then
    log "[DRY-RUN] paru -S $(grep -v '^#' "$AUR_LIST" 2>/dev/null | tr '\n' ' ')"
    return 0
  fi
  if [[ ! -f "$AUR_LIST" ]]; then
    log "Liste AUR absente: $AUR_LIST"
    return 0
  fi
  local pkgs=()
  local pkg
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && pkgs+=("$pkg")
  done < <(grep -v '^#' "$AUR_LIST" | grep -v '^[[:space:]]*$' || true)
  if [[ ${#pkgs[@]} -eq 0 ]]; then
    return 0
  fi
  install_paru
  paru -S --needed --noconfirm "${pkgs[@]}"
}

configure_gaming() {
  log "Configuration gaming (Steam, Proton, gamemode)"
  if is_dry_run; then
    log "[DRY-RUN] steam gamemode mangohud"
    return 0
  fi
  enable_multilib
  sudo pacman -S --needed --noconfirm steam gamemode mangohud 2>/dev/null || true
  mkdir -p ~/.config/environment.d
  cat > ~/.config/environment.d/gaming.conf <<'EOF'
# Variables pour gaming Vulkan/DX12
VKD3D_CONFIG=dxr
PROTON_ENABLE_NVAPI=0
EOF
}

configure_video() {
  log "Configuration création vidéo"
  if is_dry_run; then return 0; fi
  sudo pacman -S --needed --noconfirm obs-studio kdenlive ffmpeg intel-media-driver libva-utils 2>/dev/null || true
  echo 'LIBVA_DRIVER_NAME=iHD' >> ~/.config/environment.d/gaming.conf 2>/dev/null || \
    mkdir -p ~/.config/environment.d && echo 'LIBVA_DRIVER_NAME=iHD' > ~/.config/environment.d/video.conf
}

configure_docker() {
  log "Configuration Docker pour développement"
  if is_dry_run; then return 0; fi
  sudo usermod -aG docker "$USER" 2>/dev/null || true
  sudo systemctl enable --now docker 2>/dev/null || true
}

install_sddm_theme() {
  local theme_src="${1:-$SCRIPT_DIR/../dotfiles/sddm-theme}"
  if [[ ! -d "$theme_src" ]]; then
    log "Thème SDDM non trouvé: $theme_src"
    return 0
  fi
  log "Installation thème SDDM"
  if is_dry_run; then
    log "[DRY-RUN] cp theme to /usr/share/sddm/themes/honor-hypr"
    return 0
  fi
  sudo mkdir -p /usr/share/sddm/themes/honor-hypr
  sudo cp -r "$theme_src"/* /usr/share/sddm/themes/honor-hypr/
  sudo mkdir -p /etc/sddm.conf.d
  sudo tee /etc/sddm.conf.d/theme.conf > /dev/null <<'EOF'
[Theme]
Current=honor-hypr
EOF
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) export DRY_RUN=1; shift ;;
      *) shift ;;
    esac
  done

  log "=== Configuration post-installation ==="
  install_intel_drivers
  configure_pipewire
  configure_network
  configure_firewall
  configure_reflector
  configure_sddm
  install_sddm_theme
  configure_snapper
  configure_gaming
  configure_video
  configure_docker
  install_aur_packages
  log "=== Configuration terminée ==="
  log "Exécutez: ~/arch-setup/dotfiles/deploy.sh"
  log "Puis: ~/arch-setup/configure/verify-dx12.sh"
}

main "$@"
