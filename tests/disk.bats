#!/usr/bin/env bats
# Tests for install/lib/disk.sh

setup() {
  export ARCH_PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export DRY_RUN=1
  export HARDWARE_REPORT="$ARCH_PROJECT_ROOT/tests/fixtures/hardware-report.json"
  unset MOCK_UNALLOCATED_REGION
  # shellcheck source=../install/lib/common.sh
  source "$ARCH_PROJECT_ROOT/install/lib/common.sh"
  # shellcheck source=../install/lib/disk.sh
  source "$ARCH_PROJECT_ROOT/install/lib/disk.sh"
}

@test "calculate_partition_layout returns error without unallocated space" {
  # DRY_RUN=1 (mis par setup) court-circuite find_unallocated_region avant
  # même de regarder le disque : il faut désactiver le mode dry-run pour que
  # parted échoue réellement sur ce disque inexistant.
  export DRY_RUN=0
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
  [[ "$result" == "314.06" ]]
}

@test "partition_disk dry-run does not fail" {
  skip "Requires loop device or parted in CI"
}

@test "gib_to_bytes produces integer sectors base" {
  result=$(gib_to_bytes 250)
  [[ "$result" -gt 200000000000 ]]
}

@test "largest_free_region parses real parted -ms output (disk with existing partitions)" {
  # Capturé sur une VM réelle : disque GPT avec ESP + partition Windows NTFS,
  # espace libre en tête (trou d'alignement) et en fin de disque.
  result=$(printf 'BYT;\n/dev/vda:251658240s:virtblk:512:512:gpt:Virtio Block Device:;\n1:34s:2047s:2014s:free;\n1:2048s:411647s:409600s:fat32:EFI:boot, esp;\n2:411648s:73811967s:73400320s::WINDOWS:msftdata;\n1:73811968s:251658206s:177846239s:free;\n' | largest_free_region)
  [[ "$result" == "73811968:251658206" ]]
}

@test "largest_free_region returns nothing when disk has no free space" {
  result=$(printf 'BYT;\n/dev/vda:251658240s:virtblk:512:512:gpt:Virtio Block Device:;\n1:2048s:251658206s:251656159s:fat32:EFI:boot, esp;\n' | largest_free_region)
  [[ -z "$result" ]]
}

@test "efi_partition_from_lsblk matches lowercase ESP GUID reported by lsblk" {
  result=$(printf 'vda\t\t120G\t\nvda1\tc12a7328-f81f-11d2-ba4b-00a0c93ec93b\t200M\t\nvda2\tebd0a0a2-b9e5-4433-87c0-68b6b72699c7\t35G\t\n' | efi_partition_from_lsblk)
  [[ "$result" == "vda1" ]]
}

@test "efi_partition_from_lsblk finds nothing when no ESP present" {
  result=$(printf 'vda\t\t120G\t\nvda1\tebd0a0a2-b9e5-4433-87c0-68b6b72699c7\t35G\t\n' | efi_partition_from_lsblk)
  [[ -z "$result" ]]
}
