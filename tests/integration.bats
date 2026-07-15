#!/usr/bin/env bats
# Dry-run integration test for full installer

setup() {
  export ARCH_PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export DRY_RUN=1
  export HARDWARE_REPORT="$ARCH_PROJECT_ROOT/tests/fixtures/hardware-report.json"
}

@test "install.sh --help exits 0" {
  run bash "$ARCH_PROJECT_ROOT/install/install.sh" --help
  [[ $status -eq 0 ]]
  [[ "$output" == *"--dry-run"* ]]
}

@test "install.sh dry-run completes full flow" {
  run bash "$ARCH_PROJECT_ROOT/install/install.sh" \
    --dry-run \
    --disk nvme0n1 \
    --root-gib 250 \
    --user archuser \
    --password testpass \
    --report "$HARDWARE_REPORT"
  [[ $status -eq 0 ]]
  [[ "$output" == *"Installation terminée"* ]]
}

@test "setup.sh dry-run completes" {
  run bash "$ARCH_PROJECT_ROOT/configure/setup.sh" --dry-run
  [[ $status -eq 0 ]]
  [[ "$output" == *"Configuration terminée"* ]]
}

@test "verify-dx12.sh runs (may warn in container)" {
  run bash "$ARCH_PROJECT_ROOT/configure/verify-dx12.sh" || true
  [[ "$output" == *"Vérification"* ]]
}
