#!/usr/bin/env bats
# Tests for install/lib/bootloader.sh and users.sh

setup() {
  export ARCH_PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export DRY_RUN=1
  export DEFAULT_USER=testuser
  # shellcheck source=../../install/lib/common.sh
  source "$ARCH_PROJECT_ROOT/install/lib/common.sh"
  # shellcheck source=../../install/lib/disk.sh
  source "$ARCH_PROJECT_ROOT/install/lib/disk.sh"
  # shellcheck source=../../install/lib/bootloader.sh
  source "$ARCH_PROJECT_ROOT/install/lib/bootloader.sh"
  # shellcheck source=../../install/lib/users.sh
  source "$ARCH_PROJECT_ROOT/install/lib/users.sh"
}

@test "configure_locale_chroot dry-run succeeds" {
  run configure_locale_chroot /mnt Europe/Paris fr
  [[ $status -eq 0 ]]
}

@test "create_user dry-run succeeds" {
  run create_user /mnt testuser password123
  [[ $status -eq 0 ]]
}

@test "enable_services_chroot dry-run succeeds" {
  run enable_services_chroot /mnt
  [[ $status -eq 0 ]]
}

@test "install_grub_dualboot dry-run succeeds" {
  run install_grub_dualboot /mnt nvme0n1
  [[ $status -eq 0 ]]
  [[ "$output" == *"DRY-RUN"* ]] || [[ "$output" == *"grub"* ]]
}

@test "install.sh rejects systemd-boot" {
  run bash "$ARCH_PROJECT_ROOT/install/install.sh" \
    --dry-run \
    --bootloader systemd-boot \
    --disk nvme0n1 \
    --user archuser \
    --report "$ARCH_PROJECT_ROOT/tests/fixtures/hardware-report.json"
  [[ $status -eq 1 ]]
  [[ "$output" == *"systemd-boot non supporté"* ]]
}
