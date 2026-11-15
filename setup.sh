#!/usr/bin/env bash
# Install build dependencies on Debian / Ubuntu. Safe to run again.
set -euo pipefail

PKGS=(
  erofs-utils                 # needs >= 1.8 for --xattrs
  android-sdk-libsparse-utils # simg2img
  mkbootimg                   # unpack_bootimg / mkbootimg (tools/vendor_boot.py)
  apksigner zipalign smali   # smali provides baksmali
  default-jdk-headless        # javac for config/*/src
  git build-essential flex bison curl ca-certificates
  bc dwarves libelf-dev libssl-dev   # kernel/build.sh
  lz4 cpio unzip python3
)
# Debian's aapt2 cannot read Android 16 framework-res.apk
AAPT2_VER=8.7.3-12006047
AAPT2_SHA=028916a040b58f34c9c89984e1bc48f8da6581662014f2b66391860def8b9c36
# d8 (build-tools 35.0.0) and android.jar (API 35) for compiling config/*/src
SDK_URL=https://dl.google.com/android/repository
D8_SHA=305622ad00535684534eb8f742cbf5e628a9abc09d8ea4d39d1babb95bf0cee5
ANDROID_JAR_SHA=4566663c3876e022b4fa4ced8c8697c4ab1688267f090114fd92d027b32e619b
# Debian's secilc does not know newer Android policy capabilities; build AOSP's
SELINUX_REF=android17-release

SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
H="$(cd "$(dirname "$0")" && pwd)"

$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends "${PKGS[@]}"

if [ ! -x "$H/tools/bin/aapt2" ]; then
  mkdir -p "$H/tools/bin"
  j="$(mktemp)"
  curl -sSfL -o "$j" "https://dl.google.com/dl/android/maven2/com/android/tools/build/aapt2/$AAPT2_VER/aapt2-$AAPT2_VER-linux.jar"
  echo "$AAPT2_SHA  $j" | sha256sum -c - >/dev/null || { echo "aapt2 checksum mismatch"; exit 1; }
  python3 -c 'import sys,zipfile; open(sys.argv[2],"wb").write(zipfile.ZipFile(sys.argv[1]).read("aapt2"))' "$j" "$H/tools/bin/aapt2"
  chmod +x "$H/tools/bin/aapt2"; rm -f "$j"
fi

sdk_fetch() {  # sdk_fetch <zip> <member> <sha256> <dst>
  [ -f "$4" ] && echo "$3  $4" | sha256sum -c - >/dev/null 2>&1 && return 0
  mkdir -p "$(dirname "$4")"
  local z="$4.zip"   # next to the target, not in /tmp: the zips are ~60 MB
  curl -sSfL -o "$z" "$SDK_URL/$1"
  python3 -c 'import sys,zipfile; open(sys.argv[3],"wb").write(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2]))' "$z" "$2" "$4"
  rm -f "$z"
  echo "$3  $4" | sha256sum -c - >/dev/null || { echo "$(basename "$4") checksum mismatch"; rm -f "$4"; exit 1; }
}
sdk_fetch build-tools_r35_linux.zip android-15/lib/d8.jar "$D8_SHA" "$H/tools/bin/d8.jar"
sdk_fetch platform-35_r02.zip android-35/android.jar "$ANDROID_JAR_SHA" "$H/tools/bin/android.jar"

if [ ! -x /usr/local/bin/secilc ]; then
  SRC="$(mktemp -d)"
  git clone -q --depth 1 -b "$SELINUX_REF" https://android.googlesource.com/platform/external/selinux "$SRC"
  make -s -C "$SRC/libsepol/src" -j"$(nproc)" libsepol.a CFLAGS="-O2 -Wno-error" >/dev/null
  mkdir -p "$SRC/build/include/sepol"
  ln -sfn "$SRC/libsepol/cil/include/cil" "$SRC/build/include/sepol/cil"
  gcc -O2 -I"$SRC/libsepol/include" -I"$SRC/build/include" \
    -o "$SRC/secilc/secilc" "$SRC/secilc/secilc.c" "$SRC/libsepol/src/libsepol.a"
  $SUDO install -m 755 "$SRC/secilc/secilc" /usr/local/bin/secilc
  rm -rf "$SRC"
fi

fsck.erofs --help 2>&1 | grep -q -- 'xattrs' || echo "warning: fsck.erofs has no --xattrs (need erofs-utils >= 1.8)"
echo "done"
