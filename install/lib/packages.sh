#!/usr/bin/env bash
# Package list management

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$SCRIPT_DIR/../packages"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

read_package_list() {
  local profile="$1"
  local file="$PACKAGES_DIR/${profile}.txt"
  [[ -f "$file" ]] || { log_error "Liste de paquets introuvable: $file"; return 1; }
  # tr -d '\r' : au cas où le fichier a des fins de ligne CRLF (checkout
  # Windows) — un \r final invisible dans un nom de paquet fait échouer
  # pacman avec "target not found" pour absolument tout.
  tr -d '\r' < "$file" | grep -v '^#' | grep -v '^[[:space:]]*$' || true
}

merge_package_lists() {
  local profiles=("$@")
  local merged=()
  local pkg
  for profile in "${profiles[@]}"; do
    while IFS= read -r pkg; do
      merged+=("$pkg")
    done < <(read_package_list "$profile")
  done
  printf '%s\n' "${merged[@]}" | sort -u
}

get_profiles_from_report() {
  local file="${1:-$HARDWARE_REPORT}"
  local profiles=(base)
  local val
  for profile in dev gaming office video hyprland; do
    val=$(json_get "profiles.${profile}" "$file" 2>/dev/null || echo "false")
    if [[ "$val" == "true" || "$val" == "True" ]]; then
      profiles+=("$profile")
    fi
  done
  printf '%s\n' "${profiles[@]}"
}

run_pacstrap() {
  local target="${1:-/mnt}"
  local profiles=("${@:2}")
  local packages
  mapfile -t packages < <(merge_package_lists "${profiles[@]}")
  log_info "Pacstrap avec ${#packages[@]} paquets (profils: ${profiles[*]})"
  if is_dry_run; then
    log_info "[DRY-RUN] pacstrap ${packages[*]:0:5}... (${#packages[@]} total)"
    return 0
  fi
  pacstrap -K "$target" "${packages[@]}"
}

read_aur_package_list() {
  local file="$PACKAGES_DIR/aur.txt"
  [[ -f "$file" ]] || { log_error "Liste AUR introuvable: $file"; return 1; }
  tr -d '\r' < "$file" | grep -v '^#' | grep -v '^[[:space:]]*$' || true
}

refresh_mirrors_live() {
  if is_dry_run; then
    log_info "[DRY-RUN] reflector --country France --latest 10 --sort rate"
    log_info "[DRY-RUN] pacman -Sy"
    return 0
  fi
  if command -v reflector &>/dev/null; then
    reflector --country France --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
    log_info "Miroirs pacman rafraîchis via reflector"
  else
    log_warn "reflector absent, miroirs par défaut conservés"
  fi
  # L'ISO live ne synchronise jamais les bases de paquets automatiquement
  # (/var/lib/pacman/sync/ n'existe même pas au premier boot) : sans ce -Sy,
  # pacstrap échoue avec "target not found" sur absolument tous les paquets.
  pacman -Sy
  log_info "Bases de paquets pacman synchronisées"
}

enable_multilib_chroot() {
  local target="${1:-/mnt}"
  if is_dry_run; then
    log_info "[DRY-RUN] activation multilib dans $target/etc/pacman.conf"
    return 0
  fi
  if grep -q '^\[multilib\]' "$target/etc/pacman.conf"; then
    log_info "multilib déjà activé"
    return 0
  fi
  sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ {
    s/^#\[multilib\]/[multilib]/
    s/^#Include = \/etc\/pacman.d\/mirrorlist/Include = \/etc\/pacman.d\/mirrorlist/
  }' "$target/etc/pacman.conf"
  log_info "multilib activé dans le système cible"
}

configure_zram_chroot() {
  local target="${1:-/mnt}"
  if is_dry_run; then
    log_info "[DRY-RUN] zram-generator.conf dans $target/etc/systemd/"
    return 0
  fi
  mkdir -p "$target/etc/systemd"
  cat > "$target/etc/systemd/zram-generator.conf" <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
  log_info "zram-generator configuré (50 % RAM)"
}

validate_official_packages() {
  local profiles=(base dev gaming office video hyprland)
  local missing=()
  local pkg profile
  for profile in "${profiles[@]}"; do
    while IFS= read -r pkg; do
      [[ -n "$pkg" ]] || continue
      if ! pacman -Sp "$pkg" &>/dev/null; then
        missing+=("$profile:$pkg")
      fi
    done < <(read_package_list "$profile")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'Paquets introuvables dans les dépôts officiels:\n' >&2
    printf '  %s\n' "${missing[@]}" >&2
    return 1
  fi
}
