#!/usr/bin/env bash
# Disk partitioning utilities for unallocated space installation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

MIN_ROOT_GIB=50

find_unallocated_region() {
  local disk="$1"
  if [[ -n "${MOCK_UNALLOCATED_REGION:-}" ]]; then
    echo "$MOCK_UNALLOCATED_REGION"
    return 0
  fi
  if is_dry_run; then
    echo "2048:419430400"
    return 0
  fi
  parted -ms "/dev/$disk" unit s print free 2>/dev/null | \
    awk -F: '/^free/ {
      gsub(/s/,"",$2); gsub(/s/,"",$3);
      size = $3 - $2;
      if (size > max) { max = size; best = $2":"$3 }
    }
    END { if (best != "") print best }'
}

find_efi_partition() {
  local disk="$1"
  if is_dry_run; then
    echo "${disk}p1"
    return 0
  fi
  lsblk -rno NAME,PARTTYPE,SIZE,MOUNTPOINT "/dev/$disk" 2>/dev/null | \
    awk '$2=="C12A7328-F81F-11D2-BA4B-00A0C93EC93B" {print $1; exit}'
}

calculate_partition_layout() {
  local disk="$1"
  local root_gib="${2:-250}"
  local region
  region=$(find_unallocated_region "$disk")
  if [[ -z "$region" ]]; then
    echo "ERROR:no_unallocated_space"
    return 1
  fi
  local start end
  start="${region%%:*}"
  end="${region##*:}"
  local region_bytes=$(( (end - start) * 512 ))
  local min_bytes
  min_bytes=$(gib_to_bytes "$MIN_ROOT_GIB")
  if (( region_bytes < min_bytes )); then
    echo "ERROR:region_too_small"
    return 1
  fi
  local root_bytes
  root_bytes=$(gib_to_bytes "$root_gib")
  if (( root_bytes > region_bytes )); then
    root_bytes=$region_bytes
  fi
  local root_sectors=$(( root_bytes / 512 ))
  local part_end=$(( start + root_sectors ))
  if (( part_end > end )); then
    part_end=$end
  fi
  echo "${start}:${part_end}:${root_bytes}"
}

validate_disk_safe() {
  local disk="$1"
  if is_dry_run; then
    log_info "[DRY-RUN] Validation disque /dev/$disk"
    return 0
  fi
  local has_windows
  has_windows=$(lsblk -rno FSTYPE,LABEL "/dev/$disk" 2>/dev/null | grep -ci ntfs || true)
  if [[ "$has_windows" -eq 0 ]]; then
    log_warn "Aucune partition NTFS détectée sur /dev/$disk"
  fi
  local unalloc
  unalloc=$(find_unallocated_region "$disk" || true)
  [[ -n "$unalloc" ]] || { log_error "Pas d'espace non alloué sur /dev/$disk"; return 1; }
  log_info "Disque /dev/$disk validé pour installation dans l'espace libre"
}

create_btrfs_subvolumes() {
  local mount_root="$1"
  mkdir -p "$mount_root"
  if is_dry_run; then
    log_info "[DRY-RUN] mkfs.btrfs et sous-volumes sur $mount_root"
    return 0
  fi
  btrfs subvolume create "$mount_root/@"
  btrfs subvolume create "$mount_root/@home"
  btrfs subvolume create "$mount_root/@snapshots"
}

partition_disk() {
  local disk="$1"
  local root_gib="${2:-250}"
  validate_disk_safe "$disk"
  local layout
  layout=$(calculate_partition_layout "$disk" "$root_gib")
  local start="${layout%%:*}"
  local rest="${layout#*:}"
  local part_end="${rest%%:*}"
  local root_bytes="${rest##*:}"

  log_info "Partitionnement /dev/$disk: start=${start}s end=${part_end}s (~$(bytes_to_gib "$root_bytes") GiB)"

  if is_dry_run; then
    log_info "[DRY-RUN] parted /dev/$disk mkpart archroot btrfs ${start}s ${part_end}s"
    echo "/dev/${disk}pX"
    return 0
  fi

  parted -s "/dev/$disk" mkpart archroot btrfs "${start}s" "${part_end}s"
  partprobe "/dev/$disk"
  sleep 2
  local part_num
  part_num=$(parted -ms "/dev/$disk" print | tail -1 | cut -d: -f1)
  local part_dev="/dev/${disk}p${part_num}"
  if [[ ! -b "$part_dev" ]]; then
    part_dev="/dev/${disk}${part_num}"
  fi
  mkfs.btrfs -f -L archroot "$part_dev"
  echo "$part_dev"
}

mount_btrfs_layout() {
  local part_dev="$1"
  local target="${2:-/mnt}"
  if is_dry_run; then
    log_info "[DRY-RUN] mount $part_dev $target"
    return 0
  fi
  mount "$part_dev" "$target"
  create_btrfs_subvolumes "$target"
  umount "$target"
  mount -o subvol=@,compress=zstd,noatime "$part_dev" "$target"
  mkdir -p "$target/home" "$target/.snapshots"
  mount -o subvol=@home,compress=zstd,noatime "$part_dev" "$target/home"
  mount -o subvol=@snapshots,compress=zstd,noatime "$part_dev" "$target/.snapshots"
}

generate_fstab() {
  local target="${1:-/mnt}"
  if is_dry_run; then
    log_info "[DRY-RUN] genfstab $target"
    return 0
  fi
  genfstab -U "$target" >> "$target/etc/fstab"
}
