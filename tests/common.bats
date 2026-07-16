#!/usr/bin/env bats
# Tests for install/lib/common.sh

setup() {
  export ARCH_PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export DRY_RUN=1
  export HARDWARE_REPORT="$ARCH_PROJECT_ROOT/tests/fixtures/hardware-report.json"
  # shellcheck source=../install/lib/common.sh
  source "$ARCH_PROJECT_ROOT/install/lib/common.sh"
}

@test "bytes_to_gib converts correctly" {
  result=$(bytes_to_gib 1073741824)
  [[ "$result" == "1.00" ]]
}

@test "gib_to_bytes converts correctly" {
  result=$(gib_to_bytes 1)
  [[ "$result" == "1073741824" ]]
}

@test "is_dry_run returns true when DRY_RUN=1" {
  export DRY_RUN=1
  run is_dry_run
  [[ $status -eq 0 ]]
}

@test "validate_hardware_report accepts valid fixture" {
  run validate_hardware_report "$HARDWARE_REPORT"
  [[ $status -eq 0 ]]
}

@test "validate_hardware_report rejects missing file" {
  run validate_hardware_report "/nonexistent/report.json"
  [[ $status -eq 1 ]]
}

@test "json_get reads schemaVersion" {
  result=$(json_get 'schemaVersion' "$HARDWARE_REPORT")
  [[ "$result" == "1.0.0" ]]
}

@test "json_get reads install.targetDisk" {
  result=$(json_get 'install.targetDisk' "$HARDWARE_REPORT")
  [[ "$result" == "0" ]]
}
