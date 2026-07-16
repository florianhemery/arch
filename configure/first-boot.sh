#!/usr/bin/env bash
# Raccourci post-installation — appelé depuis ~/arch-setup/configure/
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH_SETUP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
exec "$ARCH_SETUP_ROOT/arch-setup" first-boot "$@"
