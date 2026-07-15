#!/usr/bin/env bash
# Verify DX12 readiness via Vulkan and vkd3d-proton

set -euo pipefail

PASS=0
FAIL=0
WARN=0

check() {
  local name="$1"
  local result="$2"
  local msg="${3:-}"
  case "$result" in
    pass) echo "[PASS] $name${msg:+: $msg}"; ((PASS++)) ;;
    fail) echo "[FAIL] $name${msg:+: $msg}"; ((FAIL++)) ;;
    warn) echo "[WARN] $name${msg:+: $msg}"; ((WARN++)) ;;
  esac
}

check_command() {
  local cmd="$1"
  if command -v "$cmd" &>/dev/null; then
    check "$cmd installed" pass
  else
    check "$cmd installed" fail "commande introuvable"
  fi
}

check_vulkan() {
  if ! command -v vulkaninfo &>/dev/null; then
    check "Vulkan runtime" fail "vulkaninfo absent"
    return
  fi
  local output
  output=$(vulkaninfo --summary 2>/dev/null || true)
  if echo "$output" | grep -qi 'intel\|anv'; then
    check "Vulkan Intel driver" pass "ANV détecté"
  else
    check "Vulkan Intel driver" warn "pilote Intel non confirmé"
  fi
  if echo "$output" | grep -q 'Vulkan Instance Version: 1\.[3-9]'; then
    check "Vulkan 1.3+" pass
  else
    check "Vulkan 1.3+" warn "version non confirmée"
  fi
}

check_vkd3d() {
  local paths=(
    "$HOME/.local/share/Steam/steamapps/common/Proton"*
    "/usr/lib/wine/vkd3d"
    "/usr/lib32/wine/vkd3d"
  )
  local found=0
  for p in "${paths[@]}"; do
    if [[ -e $p ]] 2>/dev/null; then
      found=1
      break
    fi
  done
  if command -v vkd3d-config &>/dev/null || [[ $found -eq 1 ]]; then
    check "vkd3d-proton" pass
  else
    check "vkd3d-proton" warn "installez Proton-GE via protonplus ou Steam"
  fi
}

check_mesa() {
  if pacman -Q mesa &>/dev/null 2>&1; then
    check "Mesa" pass "$(pacman -Q mesa | awk '{print $2}')"
  else
    check "Mesa" fail
  fi
}

check_steam() {
  if command -v steam &>/dev/null; then
    check "Steam" pass
  else
    check "Steam" warn "non installé"
  fi
}

check_gamemode() {
  if command -v gamemoderun &>/dev/null; then
    check "Gamemode" pass
  else
    check "Gamemode" warn
  fi
}

main() {
  echo "=== Vérification support DX12 (Vulkan/vkd3d) ==="
  check_command vulkaninfo
  check_mesa
  check_vulkan
  check_vkd3d
  check_steam
  check_gamemode

  echo ""
  echo "Résultat: $PASS pass, $WARN warn, $FAIL fail"
  if [[ $FAIL -gt 0 ]]; then
    echo "Échec: corrigez les erreurs avant de lancer des jeux DX12"
    exit 1
  fi
  if [[ $WARN -gt 0 ]]; then
    echo "Avertissements présents - gaming possible mais vérifiez Steam/Proton"
    exit 0
  fi
  echo "Système prêt pour DX12 via Proton + vkd3d-proton"
}

main "$@"
