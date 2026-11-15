#!/usr/bin/env bash
# Build facehal-rs (https://github.com/LazyBonesLZY/facehal-rs, commit ac24347) for system_ext into prebuilt/.
#
#   FACEHAL_SRC=<checkout> FACEHAL_TC=<toolchain> bash config/facehal/build_facehal.sh [work dir]
#
# facehal-systemext.patch: system libcamera2ndk instead of the vendor one, libraries in /system_ext/lib64/facehal,
# data in /data/system_de, no cargo --offline.
# Toolchain dir: rustup with the aarch64-linux-android target and NDK r27c in $FACEHAL_TC/ndk; libclang 19.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC=${FACEHAL_SRC:?set FACEHAL_SRC}
TC=${FACEHAL_TC:?set FACEHAL_TC}
WORK="${1:-$(cd "$HERE/../.." && pwd)/work}"

cd "$SRC"
if ! git diff --quiet; then
  git diff | cmp -s - "$HERE/facehal-systemext.patch" || { echo "source tree has other changes" >&2; exit 1; }
else
  git apply "$HERE/facehal-systemext.patch"
fi

# NDK r27c has no android/llndk-versioning.h
STUB="$(mktemp -d)"; mkdir -p "$STUB/android"
printf '#pragma once\n#define __INTRODUCED_IN_LLNDK(x)\n' > "$STUB/android/llndk-versioning.h"

export RUSTUP_HOME=$TC/rustup CARGO_HOME=$TC/cargo ANDROID_NDK_HOME=$TC/ndk
export PATH=$CARGO_HOME/bin:$PATH
export ANDROID_SYSTEM_LIB64=$WORK/hyperos/parts/system/system/lib64
export ANDROID_VENDOR_LIB64=$ANDROID_SYSTEM_LIB64
export LIBCLANG_PATH=/usr/lib/llvm-19/lib
export BINDGEN_EXTRA_CLANG_ARGS="-isystem $TC/ndk/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/18/include -I$STUB"sh scripts/build-production.sh

P="$HERE/prebuilt"
rm -rf "$P"; mkdir -p "$P/lib64"
install -m 0755 android.hardware.biometrics.face-service.facehal "$P/"
install -m 0644 staging/system_ext/lib64/facehal/*.so "$P/lib64/"
(cd "$P" && sha256sum android.hardware.biometrics.face-service.facehal lib64/*.so > SHA256SUMS)
rm -rf "$STUB"
echo "done: $P"
