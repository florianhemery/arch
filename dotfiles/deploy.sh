#!/usr/bin/env bash
# Deploy dotfiles with symlinks (idempotent)

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN="${DRY_RUN:-0}"
HARDWARE_REPORT="${HARDWARE_REPORT:-$DOTFILES_DIR/../analyze/hardware-report.json}"

log() { echo "[deploy] $*"; }

link_file() {
  local src="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -L "$dest" ]]; then
    local current
    current=$(readlink -f "$dest" 2>/dev/null || readlink "$dest")
    if [[ "$current" == "$(readlink -f "$src")" ]]; then
      return 0
    fi
    rm "$dest"
  elif [[ -e "$dest" ]]; then
  log "Sauvegarde: $dest -> ${dest}.bak"
    if [[ "$DRY_RUN" != "1" ]]; then
      mv "$dest" "${dest}.bak"
    fi
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY-RUN] ln -sf $src $dest"
  else
    ln -sf "$src" "$dest"
    log "Lié: $dest -> $src"
  fi
}

link_dir_contents() {
  local src_dir="$1"
  local dest_dir="$2"
  for f in "$src_dir"/*; do
    [[ -e "$f" ]] || continue
    link_file "$f" "$dest_dir/$(basename "$f")"
  done
}

generate_monitors_from_report() {
  if [[ ! -f "$HARDWARE_REPORT" ]]; then
    log "Pas de hardware-report.json, monitors.conf par défaut conservé"
    return 0
  fi
  local width height scale refresh
  width=$(python3 -c "import json; d=json.load(open('$HARDWARE_REPORT', encoding='utf-8-sig')); print(d['display']['primary']['width'])" 2>/dev/null || echo 1920)
  height=$(python3 -c "import json; d=json.load(open('$HARDWARE_REPORT', encoding='utf-8-sig')); print(d['display']['primary']['height'])" 2>/dev/null || echo 1080)
  scale=$(python3 -c "import json; d=json.load(open('$HARDWARE_REPORT', encoding='utf-8-sig')); print(d['display']['primary'].get('scale', 1.0))" 2>/dev/null || echo 1.0)
  refresh=$(python3 -c "import json; d=json.load(open('$HARDWARE_REPORT', encoding='utf-8-sig')); print(d['display']['primary'].get('refreshHz', 60))" 2>/dev/null || echo 60)
  local out="$DOTFILES_DIR/hypr/monitors.conf"
  cat > "$out" <<EOF
# Auto-generated from hardware-report.json
monitor = eDP-1, ${width}x${height}@${refresh}, 0x0, ${scale}
EOF
  log "monitors.conf généré: ${width}x${height}@${refresh} scale=${scale}"
}

deploy_hyprland() {
  mkdir -p "$HOME/.config/hypr"
  generate_monitors_from_report
  link_dir_contents "$DOTFILES_DIR/hypr" "$HOME/.config/hypr"
}

deploy_configs() {
  link_dir_contents "$DOTFILES_DIR/waybar" "$HOME/.config/waybar"
  link_file "$DOTFILES_DIR/rofi/config.rasi" "$HOME/.config/rofi/config.rasi"
  link_dir_contents "$DOTFILES_DIR/swaync" "$HOME/.config/swaync"
  link_file "$DOTFILES_DIR/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
}

deploy_wlogout() {
  mkdir -p "$HOME/.config/wlogout"
  link_file "$DOTFILES_DIR/wlogout/layout" "$HOME/.config/wlogout/layout"
  link_file "$DOTFILES_DIR/wlogout/style.css" "$HOME/.config/wlogout/style.css"
}

deploy_shell() {
  link_file "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"
  mkdir -p "$HOME/.config"
  link_file "$DOTFILES_DIR/zsh/starship.toml" "$HOME/.config/starship.toml"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) export DRY_RUN=1; shift ;;
      --report) export HARDWARE_REPORT="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  log "=== Déploiement dotfiles Hyprland ==="
  deploy_hyprland
  deploy_configs
  deploy_wlogout
  deploy_shell
  log "=== Déploiement terminé ==="
  log "Redémarrez ou relancez Hyprland pour appliquer"
}

main "$@"
