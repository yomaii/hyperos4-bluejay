#!/usr/bin/env bash
# Unpack the HyperOS OTA package (payload.bin) and the Pixel 6a factory image.
#
#   sudo ./unpack.sh --hyperos <madrid-ota_full-*.zip> --pixel <bluejay-*-factory-*.zip> [--work DIR] [--clean]
#
#   --work DIR   default ./work; must be on a Linux filesystem (owners and xattrs are kept)
#   --clean      remove the extracted zip contents afterwards
#
# Result: work/{hyperos,pixel}/parts/<partition>/ with owners, modes, SELinux labels and capabilities.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="$HERE/tools"
PY="python3 -I"
HYPEROS_ZIP="" PIXEL_ZIP="" CLEAN=0
WORK="$HERE/work"
FS_PARTS=(system system_ext product mi_ext mi_product vendor odm)

die()  { echo "error: $*" >&2; exit 1; }
log()  { echo -e "\033[1;36m==> $*\033[0m"; }
info() { echo "    $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --hyperos) HYPEROS_ZIP="$2"; shift 2 ;;
    --pixel)   PIXEL_ZIP="$2"; shift 2 ;;
    --work)    WORK="$2"; shift 2 ;;
    --clean)   CLEAN=1; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
done
[ -n "$HYPEROS_ZIP" ] && [ -n "$PIXEL_ZIP" ] || die "need --hyperos and --pixel"
[ "$(id -u)" -eq 0 ] || die "run as root (file owners and SELinux labels must be kept)"
for t in unzip simg2img fsck.erofs python3; do
  command -v "$t" >/dev/null || die "$t not found, run setup.sh"
done
mkdir -p "$WORK"; WORK="$(readlink -f "$WORK")"

magic() { od -An -tx1 -j "$2" -N "$3" "$1" | tr -d ' \n'; }   # magic <file> <offset> <bytes>

extract_fs() {   # extract_fs <image> <out_dir>
  local img="$1" out="$2" t mnt
  if [ "$(magic "$img" 0 4)" = 3aff26ed ]; then   # Android sparse
    simg2img "$img" "$img.raw"; rm -f "$img"; mv "$img.raw" "$img"
  fi
  t=unknown
  [ "$(magic "$img" 1024 4)" = e2e1f5e0 ] && t=erofs
  [ "$(magic "$img" 1080 2)" = 53ef ] && t=ext4
  rm -rf "$out"; mkdir -p "$out"
  case "$t" in
    erofs)
      fsck.erofs --extract="$out" --xattrs --preserve --overwrite "$img" >/dev/null
      # fsck.erofs sets xattrs before chown, and chown clears file capabilities.
      # Extract again without owners and copy the capabilities over.
      rm -rf "$out.caps"; mkdir -p "$out.caps"
      fsck.erofs --extract="$out.caps" --xattrs --no-preserve-owner --overwrite "$img" >/dev/null
      $PY "$TOOLS/copy_caps.py" "$out.caps" "$out"
      rm -rf "$out.caps" ;;
    ext4)
      mnt="$(mktemp -d)"
      mount -o loop,ro "$img" "$mnt"; cp -a "$mnt/." "$out/"; umount "$mnt"; rmdir "$mnt" ;;
    *) die "$(basename "$img"): unknown filesystem ($t)" ;;
  esac
  info "$(basename "$img") ($t) -> parts/$(basename "$out")  $(du -sh "$out" | cut -f1)"
}

process_rom() {   # process_rom <name> <zip>
  local name="$1" zip="$2" base="$WORK/$1" raw="$WORK/$1/raw" images="$WORK/$1/images" f p
  [ -f "$zip" ] || die "$zip not found"
  log "[$name] $(basename "$zip")"
  rm -rf "$raw" "$images" "$base/parts"; mkdir -p "$raw" "$images" "$base/parts"
  if unzip -Z1 "$zip" | grep -qx payload.bin; then
    $PY "$TOOLS/payload_extract.py" extract "$zip" "$images" "${FS_PARTS[@]}"
  else
    unzip -q -o "$zip" -d "$raw"
    while IFS= read -r -d '' f; do unzip -q -o "$f" -d "$raw"; rm -f "$f"; done < <(find "$raw" -name '*.zip' -print0)
    while IFS= read -r -d '' f; do ln -sf "$f" "$images/$(basename "$f")"; done < <(find "$raw" -type f -name '*.img' -print0)
  fi
  for p in "${FS_PARTS[@]}"; do
    [ -e "$images/$p.img" ] || continue
    extract_fs "$images/$p.img" "$base/parts/$p"
  done
  [ "$CLEAN" -eq 0 ] || rm -rf "$raw" "$images"
}

process_rom hyperos "$HYPEROS_ZIP"
process_rom pixel "$PIXEL_ZIP"
log "done: $WORK"
