#!/usr/bin/env bash
# Post-installation system configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/tmp/arch-configure.log}"
DRY_RUN="${DRY_RUN:-0}"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG_FILE"; }

is_dry_run() { [[ "$DRY_RUN" == "1" ]]; }

install_intel_drivers() {
  log "Configuration pilotes Intel (Mesa, Vulkan, media)"
  if is_dry_run; then
    log "[DRY-RUN] pacman -S mesa vulkan-intel intel-media-driver libva-intel-driver"
    return 0
  fi
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

configure_gaming() {
  log "Configuration gaming (Steam, Proton, gamemode)"
  if is_dry_run; then
    log "[DRY-RUN] steam gamemode protonplus"
    return 0
  fi
  # Enable multilib if not already
  if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    echo -e "\n[multilib]\nInclude = /etc/pacman.mirrorlist" | sudo tee -a /etc/pacman.conf
    sudo pacman -Sy
  fi
  sudo pacman -S --needed --noconfirm steam gamemode protonplus mangohud 2>/dev/null || true
  # Steam launch options hint
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
  sudo pacman -S --needed --noconfirm obs-studio kdenlive ffmpeg intel-media-driver 2>/dev/null || true
  # VA-API for Intel
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
  configure_sddm
  install_sddm_theme
  configure_gaming
  configure_video
  configure_docker
  log "=== Configuration terminée ==="
  log "Exécutez: ~/arch-setup/dotfiles/deploy.sh"
  log "Puis: ~/arch-setup/configure/verify-dx12.sh"
}

main "$@"
