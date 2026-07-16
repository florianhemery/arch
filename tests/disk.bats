#!/usr/bin/env bats
# Tests for install/lib/disk.sh

setup() {
  export ARCH_PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export DRY_RUN=1
  export HARDWARE_REPORT="$ARCH_PROJECT_ROOT/tests/fixtures/hardware-report.json"
  unset MOCK_UNALLOCATED_REGION
  # shellcheck source=../../install/lib/common.sh
  source "$ARCH_PROJECT_ROOT/install/lib/common.sh"
  # shellcheck source=../../install/lib/disk.sh
  source "$ARCH_PROJECT_ROOT/install/lib/disk.sh"
}

@test "calculate_partition_layout returns error without unallocated space" {
  run calculate_partition_layout "nonexistentdisk999" 250
  [[ $status -eq 1 ]]
}

@test "calculate_partition_layout rejects region smaller than 50 GiB" {
  export MOCK_UNALLOCATED_REGION="2048:106496"
  run calculate_partition_layout "mockdisk" 250
  [[ $status -eq 1 ]]
  [[ "$output" == *"region_too_small"* ]]
}

@test "calculate_partition_layout accepts region >= 50 GiB" {
  export MOCK_UNALLOCATED_REGION="2048:419430400"
  run calculate_partition_layout "mockdisk" 250
  [[ $status -eq 0 ]]
  [[ "$output" == *":"* ]]
}

@test "bytes_to_gib via common for large values" {
  result=$(bytes_to_gib 337222451200)
  [[ "$result" == "314.00" ]] || [[ "$result" == "313.99" ]] || [[ "$result" == "314.01" ]]
}

@test "partition_disk dry-run does not fail" {
  skip "Requires loop device or parted in CI"
}

@test "gib_to_bytes produces integer sectors base" {
  result=$(gib_to_bytes 250)
  [[ "$result" -gt 200000000000 ]]
}
