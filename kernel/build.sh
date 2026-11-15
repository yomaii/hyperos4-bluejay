#!/usr/bin/env bash
# Build the kernel modules as GKI external modules for the stock Pixel 6a kernel.
#
#   ./kernel/build.sh [--images DIR] [--kbuild DIR] [--out DIR]
#
#   --images DIR  Pixel factory images with boot.img and vendor_boot.img (default: work/pixel/images from unpack.sh)
#   --kbuild DIR  kernel sources, clang and build tree, about 4 GB (default: work/kernel)
#   --out DIR     where the modules go (default: out/kernel)
#
# The kernel config is taken from boot.img and the symbol CRCs from the stock modules in vendor_boot.img.
# Output: panel-samsung-s6e3fc3_6a.ko (60/90Hz), port_gamma.ko, port_thermal.ko.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
IMAGES="$REPO/work/pixel/images"; KB="$REPO/work/kernel"; OUT="$REPO/out/kernel"

# Sources for CP2A.260705.006. The CP2A device modules are not published, so the android16 branch is used
# (see the struct exynos_panel padding below).
GKI=bd23337e42e794964a89f47596daf1209a25ee1a   # 6.1.157-android14-11-gbd23337e42e7
SRC=(
  "common         kernel/common                          $GKI"
  "bluejay        kernel/devices/google/bluejay          eaeadd8bebb00615ddf305d4423d9c459cff36bf"
  "samsung        kernel/google-modules/display/samsung  2606e7143f21c4ff9be51d94922c1106a3aec071"
  "display-common kernel/google-modules/display/common   e34756e6205a16083c5c7c4e5cde2c899674a120"
  "soc-gs         kernel/google-modules/soc/gs           204078758737776959ecc85c527a00fd2cabb62f"
)
CLANG=clang-r487747c   # the toolchain the GKI kernel was built with

die()  { echo "error: $*" >&2; exit 1; }
log()  { echo -e "\033[1;36m==> $*\033[0m"; }
info() { echo "    $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --images) IMAGES="$2"; shift 2 ;;
    --kbuild) KB="$2"; shift 2 ;;
    --out)    OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
done
for t in git curl make bc pahole flex bison lz4 cpio unpack_bootimg python3; do
  command -v "$t" >/dev/null || die "$t not found, run setup.sh"
done
for f in boot.img vendor_boot.img; do
  [ -f "$IMAGES/$f" ] || die "$IMAGES/$f not found (run unpack.sh without --clean, or pass --images)"
done
mkdir -p "$KB" "$OUT"; KB="$(readlink -f "$KB")"; OUT="$(readlink -f "$OUT")"; IMAGES="$(readlink -f "$IMAGES")"
export TMPDIR="$KB/tmp"; rm -rf "$TMPDIR"; mkdir -p "$TMPDIR"

# ---------------------------------------------------------------- sources
log "sources"
for s in "${SRC[@]}"; do
  read -r dir repo rev <<< "$s"
  if [ "$(git -C "$KB/$dir" rev-parse HEAD 2>/dev/null)" != "$rev" ]; then
    [ -d "$KB/$dir/.git" ] || git init -q "$KB/$dir"
    git -C "$KB/$dir" fetch -q --depth 1 "https://android.googlesource.com/$repo" "$rev"
    git -C "$KB/$dir" checkout -q -f FETCH_HEAD
  fi
  info "$dir ${rev:0:12}"
done
if [ ! -x "$KB/$CLANG/bin/clang" ]; then
  mkdir -p "$KB/$CLANG"
  for ref in main android14-release llvm-r487747; do
    url="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/$ref/$CLANG.tar.gz"
    if curl -sfL "$url" -o "$TMPDIR/clang.tgz" && [ "$(stat -c%s "$TMPDIR/clang.tgz")" -gt 100000000 ]; then
      tar -xzf "$TMPDIR/clang.tgz" -C "$KB/$CLANG"; rm -f "$TMPDIR/clang.tgz"; break
    fi
  done
  [ -x "$KB/$CLANG/bin/clang" ] || die "could not download $CLANG"
fi
export PATH="$KB/$CLANG/bin:$PATH"
info "$("$KB/$CLANG/bin/clang" --version | head -1)"
MK=(make -s -C "$KB/common" ARCH=arm64 LLVM=1 LLVM_IAS=1 O="$KB/out-common")

# ---------------------------------------------------------------- kernel config and symbol CRCs
log "config and CRCs from the factory images"
W="$TMPDIR/img"; mkdir -p "$W"
unpack_bootimg --boot_img "$IMAGES/boot.img" --out "$W/boot" >/dev/null
lz4 -dc "$W/boot/kernel" > "$W/Image"
ver="$(grep -a -m1 -o 'Linux version [^ ]*' "$W/Image" | cut -d' ' -f3)"
[[ "$ver" == *"-g${GKI:0:12}-"* ]] || die "boot.img runs $ver; the sources here are for g${GKI:0:12}"
info "kernel $ver"
bash "$KB/common/scripts/extract-ikconfig" "$W/Image" > "$W/config" || die "no config in boot.img"
unpack_bootimg --boot_img "$IMAGES/vendor_boot.img" --out "$W/vb" >/dev/null
for r in "$W"/vb/vendor_ramdisk*; do
  d="$W/mods/$(basename "$r")"; mkdir -p "$d"
  (cd "$d" && lz4 -dc "$r" | cpio -idm --quiet 2>/dev/null) || true
done
python3 -I "$HERE/symvers_from_stock.py" "$W/stock.symvers" "$W/mods" | sed 's/^/    /'

if [ ! -f "$KB/out-common/.prepared" ] || ! cmp -s "$W/config" "$KB/config.device" \
   || ! cmp -s "$W/stock.symvers" "$KB/stock.symvers"; then
  log "modules_prepare"
  cp "$W/config" "$KB/config.device"; cp "$W/stock.symvers" "$KB/stock.symvers"
  # CONFIG_TRIM_UNUSED_KSYMS: the kernel keeps only the symbols listed here
  cut -f2 "$KB/stock.symvers" > "$KB/common/abi_symbollist.raw"
  rm -rf "$KB/out-common"; mkdir -p "$KB/out-common"
  cp "$KB/config.device" "$KB/out-common/.config"
  "${MK[@]}" olddefconfig
  # options probed from the host toolchain do not affect the module ABI
  HOSTONLY='^CONFIG_(CC_CAN_LINK|CC_CAN_LINK_STATIC|UAPI_HEADER_TEST|PAHOLE_VERSION|PAHOLE_HAS_LANG_EXCLUDE)='
  diff <(grep -v '^#' "$KB/config.device" | grep -Ev "$HOSTONLY" | sort -u) \
       <(grep -v '^#' "$KB/out-common/.config" | grep -Ev "$HOSTONLY" | sort -u) \
    || die "olddefconfig changed the device config (wrong sources or toolchain?)"
  "${MK[@]}" modules_prepare
  cp "$KB/stock.symvers" "$KB/out-common/Module.symvers"
  touch "$KB/out-common/.prepared"
fi

# CP2A's struct exynos_panel is 8 bytes larger than in the android16 sources: offsets match up to dimming_on
# (2480), everything from panel_rev (2824) on is shifted by 8, and the driver touches nothing in between.
# Padding before panel_rev makes the unpatched driver build instruction-identical to the stock module.
H="$KB/samsung/panel/panel-samsung-drv.h"
if ! grep -q port_cp2a_pad "$H"; then
  python3 -I - "$H" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '\tchar panel_model[PANEL_MODEL_MAX];\n\tu32 panel_rev;\n'
assert s.count(old) == 1, 'panel_model/panel_rev not found'
s = s.replace(old, '\tchar panel_model[PANEL_MODEL_MAX];\n\tu64 port_cp2a_pad; /* CP2A: +8 bytes before panel_rev */\n\tu32 panel_rev;\n')
open(p, 'w').write(s)
PY
fi

# ---------------------------------------------------------------- modules
build() {  # build <name> <extra symvers or ""> ; sources already in $KB/mod/<name>
  local M="$KB/mod/$1" known="$TMPDIR/known"
  "${MK[@]}" M="$M" W=1 ${2:+KBUILD_EXTRA_SYMBOLS="$2"} modules
  cut -f2 "$KB/stock.symvers" ${2:+"$2"} | sort -u > "$known"
  missing="$(llvm-nm -u "$M/$1.ko" | awk '{print $2}' | sort -u | comm -23 - "$known")"
  [ -z "$missing" ] || die "$1.ko needs symbols the stock kernel does not export: $missing"
  llvm-strip --strip-debug -o "$OUT/$1.ko" "$M/$1.ko"
  info "$1.ko  $(stat -c%s "$OUT/$1.ko") bytes"
}
log "modules"
rm -rf "$KB/mod"; mkdir -p "$KB/mod/panel-samsung-s6e3fc3_6a" "$KB/mod/port_gamma" "$KB/mod/port_thermal"

M="$KB/mod/panel-samsung-s6e3fc3_6a"
cp "$KB/bluejay/display/panel-samsung-s6e3fc3_6a.c" "$M/"
patch -s -d "$M" -p2 < "$HERE/bluejay-90hz-gamma/panel-90hz.patch"
cat > "$M/Kbuild" <<EOF
obj-m += panel-samsung-s6e3fc3_6a.o
ccflags-y += -DDYNAMIC_DEBUG_MODULE=1 -Werror
ccflags-y += -fmacro-prefix-map=$KB/=   # no local paths in __FILE__
ccflags-y += -I$KB/display-common/include
ccflags-y += -I$KB/samsung -I$KB/samsung/include/uapi
ccflags-y += -I$KB/soc-gs/include
EOF
build panel-samsung-s6e3fc3_6a ""

cp "$HERE"/bluejay-90hz-gamma/port_gamma/*.[ch] "$KB/mod/port_gamma/"
printf 'obj-m += port_gamma.o\nccflags-y += -Werror\n' > "$KB/mod/port_gamma/Kbuild"
build port_gamma ""

# thermal_zone_get_* are exported by the phone kernel but missing from the stock modules' CRCs
cp "$HERE/port_thermal/port_thermal.c" "$HERE/port_thermal/Kbuild" "$KB/mod/port_thermal/"
build port_thermal "$HERE/port_thermal/extra.symvers"

rm -rf "$TMPDIR"
log "done: $OUT"
