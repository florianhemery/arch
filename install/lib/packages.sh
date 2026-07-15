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
  grep -v '^#' "$file" | grep -v '^[[:space:]]*$' || true
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
