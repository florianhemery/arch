#!/usr/bin/env bash
# Portable bash test runner (no bats/shellcheck required)
# Used when Docker/WSL packages are unavailable

set -euo pipefail

ARCH_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ARCH_PROJECT_ROOT
export DRY_RUN=1
export HARDWARE_REPORT="$ARCH_PROJECT_ROOT/tests/fixtures/hardware-report.json"

PASS=0
FAIL=0
SKIP=0

pass() { echo "[PASS] $1"; ((PASS++)) || true; }
fail() { echo "[FAIL] $1"; ((FAIL++)) || true; }
skip() { echo "[SKIP] $1"; ((SKIP++)) || true; }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$desc"
  else
    fail "$desc (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc (missing '$needle')"
  fi
}

assert_success() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc (command failed: $*)"
  fi
}

assert_file_exists() {
  local desc="$1" file="$2"
  if [[ -f "$file" ]]; then
    pass "$desc"
  else
    fail "$desc (file not found: $file)"
  fi
}

# --- Load modules ---
# shellcheck source=../install/lib/common.sh
source "$ARCH_PROJECT_ROOT/install/lib/common.sh"
# shellcheck source=../install/lib/disk.sh
source "$ARCH_PROJECT_ROOT/install/lib/disk.sh"
# shellcheck source=../install/lib/packages.sh
source "$ARCH_PROJECT_ROOT/install/lib/packages.sh"
# shellcheck source=../install/lib/bootloader.sh
source "$ARCH_PROJECT_ROOT/install/lib/bootloader.sh"
# shellcheck source=../install/lib/users.sh
source "$ARCH_PROJECT_ROOT/install/lib/users.sh"

echo "=== Tests bash portables ==="

# common.sh
assert_eq "bytes_to_gib" "1.00" "$(bytes_to_gib 1073741824)"
assert_eq "gib_to_bytes" "1073741824" "$(gib_to_bytes 1)"
assert_success "validate_hardware_report" validate_hardware_report "$HARDWARE_REPORT"
assert_eq "json_get schemaVersion" "1.0.0" "$(json_get schemaVersion "$HARDWARE_REPORT")"
assert_eq "json_get targetDisk" "0" "$(json_get install.targetDisk "$HARDWARE_REPORT")"

# packages.sh
assert_contains "base packages has linux" "linux" "$(read_package_list base)"
assert_contains "gaming has vulkan-intel" "vulkan-intel" "$(read_package_list gaming)"
assert_contains "hyprland has sddm" "sddm" "$(read_package_list hyprland)"
assert_contains "aur has protonplus" "protonplus" "$(read_aur_package_list)"
assert_contains "aur has wlogout" "wlogout" "$(read_aur_package_list)"
assert_contains "profiles include gaming" "gaming" "$(get_profiles_from_report "$HARDWARE_REPORT")"

# disk.sh — region too small
export MOCK_UNALLOCATED_REGION="2048:106496"
output=$(calculate_partition_layout mockdisk 250 2>&1) || true
if [[ "$output" == *region_too_small* ]]; then
  pass "disk rejects small unallocated region"
else
  fail "disk rejects small unallocated region (got: $output)"
fi
unset MOCK_UNALLOCATED_REGION
export MOCK_UNALLOCATED_REGION="2048:419430400"
output=$(calculate_partition_layout mockdisk 250 2>&1) || true
if [[ "$output" == *":"* && "$output" != *region_too_small* ]]; then
  pass "disk accepts large unallocated region"
else
  fail "disk accepts large unallocated region (got: $output)"
fi
unset MOCK_UNALLOCATED_REGION

# bootloader/users dry-run
assert_success "configure_locale_chroot dry-run" configure_locale_chroot /mnt Europe/Paris fr
assert_success "create_user dry-run" create_user /mnt testuser pass
assert_success "enable_services dry-run" enable_services_chroot /mnt

# dotfiles
assert_file_exists "hyprland.conf" "$ARCH_PROJECT_ROOT/dotfiles/hypr/hyprland.conf"
assert_contains "hyprland binds" "bind = SUPER, Return" "$(cat "$ARCH_PROJECT_ROOT/dotfiles/hypr/hyprland.conf")"
assert_success "waybar json valid" python3 -m json.tool "$ARCH_PROJECT_ROOT/dotfiles/waybar/config.json"
assert_success "swaync json valid" python3 -m json.tool "$ARCH_PROJECT_ROOT/dotfiles/swaync/config.json"

# integration dry-run
output=$(bash "$ARCH_PROJECT_ROOT/install/install.sh" --dry-run --disk nvme0n1 --user archuser --password test --report "$HARDWARE_REPORT" 2>&1)
assert_contains "install dry-run complete" "Installation terminée" "$output"
assert_contains "install dry-run mentions first-boot" "first-boot" "$output"

output=$(bash "$ARCH_PROJECT_ROOT/arch-setup" live --dry-run --disk nvme0n1 --user archuser --password test --report "$HARDWARE_REPORT" 2>&1)
assert_contains "arch-setup live dry-run" "Installation terminée" "$output"

output=$(bash "$ARCH_PROJECT_ROOT/configure/setup.sh" --dry-run 2>&1)
assert_contains "setup dry-run complete" "Configuration terminée" "$output"

output=$(bash "$ARCH_PROJECT_ROOT/configure/verify-dx12.sh" 2>&1) || true
assert_contains "verify-dx12 completes" "Résultat:" "$output"

# jsonschema validation
if python3 -c "import jsonschema" 2>/dev/null; then
  assert_success "fixture validates against schema" python3 -c "
import json, jsonschema
schema = json.load(open('$ARCH_PROJECT_ROOT/analyze/hardware-report.schema.json'))
report = json.load(open('$HARDWARE_REPORT', encoding='utf-8-sig'))
jsonschema.validate(report, schema)
"
else
  skip "jsonschema python module unavailable"
fi

output=$(bash "$ARCH_PROJECT_ROOT/dotfiles/deploy.sh" --dry-run 2>&1)
assert_contains "deploy dry-run complete" "Déploiement terminé" "$output"

# Résolution de shellcheck : PATH, puis cache local, puis téléchargement du binaire statique
resolve_shellcheck() {
  if command -v shellcheck &>/dev/null; then
    command -v shellcheck
    return 0
  fi
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/arch-tests"
  local cached="$cache_dir/shellcheck"
  if [[ -x "$cached" ]]; then
    echo "$cached"
    return 0
  fi
  local arch
  arch=$(uname -m)
  [[ "$arch" == "x86_64" || "$arch" == "aarch64" ]] || return 1
  local url="https://github.com/koalaman/shellcheck/releases/download/stable/shellcheck-stable.linux.${arch}.tar.xz"
  mkdir -p "$cache_dir"
  local tmp
  tmp=$(mktemp -d)
  if command -v curl &>/dev/null; then
    curl -fsSL "$url" -o "$tmp/sc.tar.xz" 2>/dev/null || { rm -rf "$tmp"; return 1; }
  elif command -v wget &>/dev/null; then
    wget -qO "$tmp/sc.tar.xz" "$url" 2>/dev/null || { rm -rf "$tmp"; return 1; }
  else
    rm -rf "$tmp"
    return 1
  fi
  tar -xJf "$tmp/sc.tar.xz" -C "$tmp" 2>/dev/null || { rm -rf "$tmp"; return 1; }
  mv "$tmp/shellcheck-stable/shellcheck" "$cached" && chmod +x "$cached"
  rm -rf "$tmp"
  [[ -x "$cached" ]] && echo "$cached"
}

SHELLCHECK_BIN=$(resolve_shellcheck || true)
if [[ -n "${SHELLCHECK_BIN:-}" ]]; then
  sc_output=$(find "$ARCH_PROJECT_ROOT/install" "$ARCH_PROJECT_ROOT/configure" "$ARCH_PROJECT_ROOT/dotfiles" "$ARCH_PROJECT_ROOT/tests" -name '*.sh' -print0 | \
     xargs -0 "$SHELLCHECK_BIN" -e SC1091,SC2034 2>&1) && sc_ok=1 || sc_ok=0
  if [[ "$sc_ok" == "1" ]]; then
    pass "shellcheck all scripts"
  else
    fail "shellcheck all scripts"
    echo "$sc_output" | head -40
  fi
else
  skip "shellcheck unavailable (PATH, cache et téléchargement KO)"
fi

echo ""
echo "Résultat: $PASS pass, $FAIL fail, $SKIP skip"
[[ $FAIL -eq 0 ]]
