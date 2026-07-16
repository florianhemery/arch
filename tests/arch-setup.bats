#!/usr/bin/env bats
# Tests for arch-setup utility

setup() {
  export ARCH_PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "arch-setup help exits 0" {
  run bash "$ARCH_PROJECT_ROOT/arch-setup" help
  [[ $status -eq 0 ]]
  [[ "$output" == *"live"* ]]
  [[ "$output" == *"first-boot"* ]]
}

@test "arch-setup find locates project root" {
  run bash "$ARCH_PROJECT_ROOT/arch-setup" find
  [[ $status -eq 0 ]]
  [[ "$output" == *"$ARCH_PROJECT_ROOT"* ]]
}

@test "arch-setup live dry-run completes" {
  export DRY_RUN=1
  run bash "$ARCH_PROJECT_ROOT/arch-setup" live \
    --dry-run \
    --disk nvme0n1 \
    --user archuser \
    --password test \
    --report "$ARCH_PROJECT_ROOT/tests/fixtures/hardware-report.json"
  [[ $status -eq 0 ]]
  [[ "$output" == *"Installation terminée"* ]]
}

@test "configure/first-boot.sh delegates to arch-setup" {
  grep -q 'arch-setup.*first-boot' "$ARCH_PROJECT_ROOT/configure/first-boot.sh"
}

@test "arch-setup.ps1 exists" {
  [[ -f "$ARCH_PROJECT_ROOT/arch-setup.ps1" ]]
}
