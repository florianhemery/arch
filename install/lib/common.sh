#!/usr/bin/env bash
# Common utilities for Arch installer modules

set -euo pipefail

ARCH_PROJECT_ROOT="${ARCH_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
HARDWARE_REPORT="${HARDWARE_REPORT:-$ARCH_PROJECT_ROOT/analyze/hardware-report.json}"
DRY_RUN="${DRY_RUN:-0}"
LOG_FILE="${LOG_FILE:-/tmp/arch-install.log}"

log() {
  local level="$1"
  shift
  local msg
  msg="[$(date -Iseconds)] [$level] $*"
  # Sur stderr, pas stdout : plusieurs fonctions (partition_disk, ...) sont
  # capturées via $(...) par leur appelant pour récupérer une valeur de
  # retour (device, chemin...). Si les logs sortaient sur stdout, ils se
  # mélangeraient à cette valeur (vu en conditions réelles : un device path
  # pollué par une ligne de log a fini interprété comme un partage NFS par
  # `mount`). Toujours visible pour l'utilisateur car les wrappers de haut
  # niveau (arch-setup) font `2>&1 | tee`.
  echo "$msg" | tee -a "$LOG_FILE" >&2
}

log_info() { log INFO "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }

require_root() {
  if is_dry_run; then
    return 0
  fi
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "Ce script doit être exécuté en root"
    exit 1
  fi
}

is_dry_run() {
  [[ "$DRY_RUN" == "1" ]]
}

bytes_to_gib() {
  awk -v b="$1" 'BEGIN { printf "%.2f", b / 1073741824 }'
}

gib_to_bytes() {
  awk -v g="$1" 'BEGIN { printf "%.0f", g * 1073741824 }'
}

json_get() {
  local key="$1"
  local file="${2:-$HARDWARE_REPORT}"
  if [[ ! -f "$file" ]]; then
    log_error "Rapport matériel introuvable: $file"
    return 1
  fi
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8-sig'))
for k in sys.argv[2].split('.'):
    d = d[k]
if isinstance(d, bool):
    print(str(d).lower())
else:
    print(d)
" "$file" "$key" 2>/dev/null || jq -er ".${key}" "$file" 2>/dev/null
}

validate_hardware_report() {
  local file="${1:-$HARDWARE_REPORT}"
  [[ -f "$file" ]] || { log_error "hardware-report.json manquant"; return 1; }
  local version
  version=$(json_get 'schemaVersion' "$file" || echo "")
  [[ "$version" == "1.0.0" ]] || { log_error "schemaVersion invalide: $version"; return 1; }
  local schema="$ARCH_PROJECT_ROOT/analyze/hardware-report.schema.json"
  if [[ -f "$schema" ]] && command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
try:
    import jsonschema
except ImportError:
    sys.exit(0)
schema = json.load(open(sys.argv[1], encoding='utf-8'))
report = json.load(open(sys.argv[2], encoding='utf-8-sig'))
jsonschema.validate(report, schema)
" "$schema" "$file" || { log_error "Rapport non conforme au schéma JSON"; return 1; }
  fi
  log_info "Rapport matériel validé: $file"
}
