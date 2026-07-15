#!/usr/bin/env bats
# Tests for install/lib/packages.sh

setup() {
  export ARCH_PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export DRY_RUN=1
  export HARDWARE_REPORT="$ARCH_PROJECT_ROOT/tests/fixtures/hardware-report.json"
  # shellcheck source=../../install/lib/common.sh
  source "$ARCH_PROJECT_ROOT/install/lib/common.sh"
  # shellcheck source=../../install/lib/packages.sh
  source "$ARCH_PROJECT_ROOT/install/lib/packages.sh"
}

@test "read_package_list loads base packages" {
  run read_package_list base
  [[ $status -eq 0 ]]
  [[ "$output" == *"linux"* ]]
  [[ "$output" == *"grub"* ]]
}

@test "read_package_list loads gaming packages with vulkan" {
  run read_package_list gaming
  [[ $status -eq 0 ]]
  [[ "$output" == *"vulkan-intel"* ]]
  [[ "$output" == *"steam"* ]]
}

@test "read_package_list loads hyprland packages" {
  run read_package_list hyprland
  [[ $status -eq 0 ]]
  [[ "$output" == *"hyprland"* ]]
  [[ "$output" == *"sddm"* ]]
}

@test "merge_package_lists deduplicates" {
  run merge_package_lists base base
  count=$(echo "$output" | wc -l)
  unique=$(echo "$output" | sort -u | wc -l)
  [[ "$count" -eq "$unique" ]]
}

@test "get_profiles_from_report includes all enabled profiles" {
  run get_profiles_from_report "$HARDWARE_REPORT"
  [[ $status -eq 0 ]]
  [[ "$output" == *"base"* ]]
  [[ "$output" == *"gaming"* ]]
  [[ "$output" == *"hyprland"* ]]
}

@test "run_pacstrap dry-run succeeds" {
  run run_pacstrap /mnt base
  [[ $status -eq 0 ]]
  [[ "$output" == *"DRY-RUN"* ]] || [[ "$output" == *"Pacstrap"* ]]
}
