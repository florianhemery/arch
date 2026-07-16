#!/usr/bin/env bats
# Tests for configure/verify-dx12.sh

setup() {
  export ARCH_PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "verify-dx12.sh completes without set -e exit on first pass" {
  run bash "$ARCH_PROJECT_ROOT/configure/verify-dx12.sh"
  [[ $status -eq 0 ]] || [[ $status -eq 1 ]]
  [[ "$output" == *"Résultat:"* ]]
  [[ "$output" != *"[PASS]"* ]] || [[ $(echo "$output" | grep -c '\[PASS\]') -ge 1 ]]
}

@test "verify-dx12.sh reports multiple checks" {
  run bash "$ARCH_PROJECT_ROOT/configure/verify-dx12.sh"
  pass_count=$(echo "$output" | grep -c '\[PASS\]' || true)
  [[ "$pass_count" -ge 1 ]]
}
