#!/usr/bin/env bats
# Tests for dotfiles and config validation

setup() {
  export ARCH_PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export DOTFILES_DIR="$ARCH_PROJECT_ROOT/dotfiles"
}

@test "hyprland.conf exists and contains key bindings" {
  [[ -f "$DOTFILES_DIR/hypr/hyprland.conf" ]]
  grep -q "bind = SUPER, Return" "$DOTFILES_DIR/hypr/hyprland.conf"
  grep -q "exec-once = waybar" "$DOTFILES_DIR/hypr/hyprland.conf"
}

@test "waybar config.json is valid JSON" {
  python3 -m json.tool "$DOTFILES_DIR/waybar/config.json" > /dev/null
}

@test "swaync config.json is valid JSON" {
  python3 -m json.tool "$DOTFILES_DIR/swaync/config.json" > /dev/null
}

@test "rofi config.rasi exists" {
  [[ -f "$DOTFILES_DIR/rofi/config.rasi" ]]
  grep -q "drun" "$DOTFILES_DIR/rofi/config.rasi"
}

@test "kitty.conf has font configured" {
  grep -q "JetBrainsMono" "$DOTFILES_DIR/kitty/kitty.conf"
}

@test "sddm theme has metadata" {
  [[ -f "$DOTFILES_DIR/sddm-theme/metadata.desktop" ]]
  grep -q "Honor Hypr" "$DOTFILES_DIR/sddm-theme/metadata.desktop"
}

@test "deploy.sh is executable logic" {
  [[ -f "$DOTFILES_DIR/deploy.sh" ]]
  grep -q "link_file" "$DOTFILES_DIR/deploy.sh"
}

@test "deploy dry-run does not error" {
  export DRY_RUN=1
  export HARDWARE_REPORT="$ARCH_PROJECT_ROOT/tests/fixtures/hardware-report.json"
  run bash "$DOTFILES_DIR/deploy.sh" --dry-run
  [[ $status -eq 0 ]]
}
