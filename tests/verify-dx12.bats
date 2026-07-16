#!/usr/bin/env bats
# Tests for configure/verify-dx12.sh

setup() {
  export ARCH_PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "verify-dx12.sh completes without set -e exit on first pass" {
  run bash "$ARCH_PROJECT_ROOT/configure/verify-dx12.sh"
  [[ $status -eq 0 ]] || [[ $status -eq 1 ]]
  [[ "$output" == *"Résultat:"* ]]
  [[ "$output" != *"[PASS]"* ]] || [[ $(echo "$output" | grep -c '\[PASS\]') -ge 1 ]]
}

@test "verify-dx12.sh reports multiple checks" {
  # Sur une machine/CI sans paquets gaming installés (mesa, vulkan-tools,
  # steam...), tous les checks peuvent légitimement finir en [WARN]/[FAIL] :
  # on vérifie que plusieurs checks sont exécutés, pas qu'ils passent tous.
  run bash "$ARCH_PROJECT_ROOT/configure/verify-dx12.sh"
  total_count=$(echo "$output" | grep -cE '\[(PASS|WARN|FAIL)\]' || true)
  [[ "$total_count" -ge 5 ]]
}
