#!/usr/bin/env bash
# Build system / system_ext / product erofs images: HyperOS 4 (madrid) on Pixel 6a (bluejay).
#
#   sudo ./build.sh [--work DIR] [--out DIR] [--no-verify] [--no-90hz]
#
#   --work DIR   output of unpack.sh (default: ./work)
#   --out DIR    where images/ goes (default: ./out); must be on a Linux filesystem
#   --no-verify  skip extracting the images again to check metadata
#   --no-90hz    for a vendor_boot without the 60/90Hz panel driver
#
# Optional inputs, skipped when missing:
#   config/facehal/prebuilt/   face unlock HAL (config/facehal/build_facehal.sh)
#   config/esim/EsimLPA.apk    Xiaomi eSIM manager (com.miui.euicc), taken from a HyperOS 3 ROM
set -euo pipefail
trap 'echo "error: line $LINENO failed (exit $?)" >&2' ERR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="$HERE/tools"; CONF="$HERE/config"; BASE="$CONF/base"
PY="python3 -I"
WORK="$HERE/work"; OUT="$HERE/out"
VERIFY=1 HZ90=1
PARTS=(system system_ext product)

die()  { echo "error: $*" >&2; exit 1; }
log()  { echo -e "\033[1;36m==> $*\033[0m"; }
info() { echo "    $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --work) WORK="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --no-verify) VERIFY=0; shift ;;
    --no-90hz) HZ90=0; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "run as root (file owners and SELinux labels must be kept)"
for t in mkfs.erofs fsck.erofs secilc python3 zipalign apksigner keytool javac java baksmali; do
  command -v "$t" >/dev/null || die "$t not found, run setup.sh"
done
AJ="$TOOLS/bin/android.jar"; D8="$TOOLS/bin/d8.jar"
[ -f "$AJ" ] && [ -f "$D8" ] || die "tools/bin/android.jar or d8.jar missing, run setup.sh"
HY="$WORK/hyperos"; PX="$WORK/pixel"
for d in "$HY/parts/system" "$HY/parts/system_ext" "$HY/parts/product" "$PX/parts/vendor"; do
  [ -e "$d" ] || die "$d not found, run unpack.sh"
done
mkdir -p "$OUT"; OUT="$(readlink -f "$OUT")"
export TMPDIR="$OUT/tmp"; rm -rf "$TMPDIR"; mkdir -p "$TMPDIR"
S="$OUT/stage"; IMG="$OUT/images"
rm -rf "$IMG" "$OUT/meta"; mkdir -p "$IMG" "$OUT/meta"
exec > >(tee "$OUT/build.log") 2>&1

prop() { [ -f "$1" ] && grep -m1 "^$2=" "$1" | cut -d= -f2- || true; }
sysroot() { [ -f "$1/system/build.prop" ] && echo "$1/system" || echo "$1"; }
label() { $PY -c 'import os,sys; os.setxattr(sys.argv[1], "security.selinux", sys.argv[2].encode()+b"\0")' "$1" "u:object_r:$2:s0"; }
setlabel() { label "$1" system_file; }
SEPOL_EXT() { echo "$S/system_ext/etc/selinux/system_ext_sepolicy.cil"; }
add_cil() { { printf '\n; port: %s\n' "${1#$HERE/}"; grep -vE '^\s*(;|$)' "$1"; } >> "$(SEPOL_EXT)"; }
append() {  # append <file> <line>...
  local f="$1"; shift
  [ -z "$(tail -c1 "$f")" ] || echo >> "$f"
  printf '%s\n' "$@" >> "$f"
}
mkdir_l() {  # mkdir -p, labelling each new level system_file
  [ -d "$1" ] && return 0
  mkdir_l "$(dirname "$1")"
  install -d -m 0755 -o root -g root "$1"; setlabel "$1"
}
inst() {  # inst <mode> <src> <dst>
  mkdir_l "$(dirname "$3")"; install -m "$1" -o root -g root "$2" "$3"; setlabel "$3"
}
KS="$WORK/port-overlay.jks"
sign_to() {  # sign_to <unsigned apk> <dst>
  zipalign -p -f 4 "$1" "$1.a" || die "zipalign failed"
  apksigner sign --ks "$KS" --ks-pass pass:android --key-pass pass:android --out "$1.s" "$1.a" || die "apksigner failed"
  install -m 0644 -o root -g root "$1.s" "$2"; setlabel "$2"
  rm -f "$1" "$1.a" "$1.s" "$1.s.idsig"
}
# Platform-signed apps cannot be re-signed: patch smali, then graft the original signing block back.
# /system apps are not digest-checked at boot.
smali_graft() {  # smali_graft <apk> <patch>
  local T; T=$(mktemp -d)
  $PY "$TOOLS/apk_smali_patch.py" "$1" "$T/u.apk" "$2" | sed 's/^/    /'
  [ "${PIPESTATUS[0]}" -eq 0 ] || die "$(basename "$2") failed (different app version?)"
  zipalign -p -f 4 "$T/u.apk" "$T/a.apk" || die "zipalign failed"
  $PY "$TOOLS/apk_sig_graft.py" "$1" "$T/a.apk" "$T/g.apk" | sed 's/^/    /'
  [ "${PIPESTATUS[0]}" -eq 0 ] || die "signature graft failed: $1"
  cat "$T/g.apk" > "$1"; rm -rf "$T"   # rewrite in place to keep owner and label
}
jar_smali() {  # jar_smali <jar> <host class> <files>...
  $PY "$TOOLS/jar_smali.py" "$@" | sed 's/^/    /'
  [ "${PIPESTATUS[0]}" -eq 0 ] || die "$(basename "$1") patch on $2 failed (different version?)"
}
java2smali() {  # java2smali <config dir> <out>: compile <dir>/src to smali; <dir>/stubs is compile-only
  local T; T=$(mktemp -d); mkdir -p "$T/stub" "$T/cls" "$T/dex"
  local JC=(javac -encoding UTF-8 -nowarn -Xlint:-options -source 17 -target 17)
  "${JC[@]}" -cp "$AJ" -d "$T/stub" $(find "$1/stubs" -name '*.java')
  # stubs first: they shadow android.jar classes that lack hidden methods (android.os.Debug)
  "${JC[@]}" -cp "$T/stub:$AJ" -d "$T/cls" $(find "$1/src" -name '*.java')
  java -cp "$D8" com.android.tools.r8.D8 --release --min-api 34 --lib "$AJ" --output "$T/dex" $(find "$T/cls" -name '*.class')
  rm -rf "$2"; baksmali d "$T/dex/classes.dex" -o "$2"; rm -rf "$T"
}
orig_class() {  # orig_class <jar> <class> <out dir>: disassemble one class of a jar
  local T x; T=$(mktemp -d)
  unzip -q -o "$1" 'classes*.dex' -d "$T"
  for x in "$T"/classes*.dex; do baksmali d --classes "L$2;" "$x" -o "$3"; done
  rm -rf "$T"
}

PX_DEVICE="$(prop "$PX/parts/vendor/build.prop" ro.product.vendor.device)"
HY_DEVICE="$(prop "$HY/parts/odm/etc/build.prop" ro.product.odm.device)"
[ -n "$HY_DEVICE" ] || HY_DEVICE="$(ls "$HY/parts/product/etc/device_features" 2>/dev/null | head -1 | sed 's/\.xml$//')"
[ -n "$PX_DEVICE" ] || die "cannot read ro.product.vendor.device from the Pixel vendor"
[ -f "$KS" ] || keytool -genkeypair -keystore "$KS" -alias port -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass android -keypass android -dname "CN=hyperos-port overlay" >/dev/null 2>&1 || die "keytool failed"
log "HyperOS ${HY_DEVICE:-?} -> Pixel $PX_DEVICE"

# ---------------------------------------------------------------- 1
log "1/6 copy HyperOS partitions"
rm -rf "$S"; mkdir -p "$S"
for p in "${PARTS[@]}"; do
  cp -a "$HY/parts/$p" "$S/$p"
  info "$p  $(du -sh "$S/$p" | cut -f1)"
done
SR="$(sysroot "$S/system")"

# ---------------------------------------------------------------- 2
log "2/6 merge mi_ext / mi_product / pangu"
M="$HY/parts/mi_ext"
if [ -d "$M" ]; then
  for sub in product system system_ext; do
    [ -d "$M/$sub" ] || continue
    case "$sub" in system) dst="$SR" ;; *) dst="$S/$sub" ;; esac
    cp -a --remove-destination "$M/$sub/." "$dst/"
    info "mi_ext/$sub -> $sub: $(find "$M/$sub" -type f | wc -l) files"
  done
  [ -f "$M/etc/build.prop" ] && $PY "$TOOLS/props.py" merge "$S/product/etc/build.prop" "$M/etc/build.prop" "merged from mi_ext/etc/build.prop"
fi
MP="$HY/parts/mi_product"
if [ -f "$MP/etc/build.prop" ]; then
  $PY "$TOOLS/props.py" merge "$S/product/etc/build.prop" "$MP/etc/build.prop" "merged from mi_product/etc/build.prop"
  [ "$(cd "$MP" && find . -type f ! -path ./etc/build.prop | wc -l)" -eq 0 ] || die "mi_product has files besides etc/build.prop"
fi

n=0
while read -r e _; do
  case "${e%%/*}" in system) t="$SR/${e#*/}" ;; *) t="$S/$e" ;; esac
  [ -e "$t" ] || die "remove.txt: $e does not exist"
  rm -rf "$t"; n=$((n+1))
done < <(grep -vE '^\s*(#|$)' "$BASE/remove.txt")
info "remove.txt: $n entries removed"

# product/pangu/system is overlay-mounted on /system by Xiaomi's vendor fstab; with the Pixel vendor
# nothing mounts it (no NFC app, among others), so merge it into system.
PG="$S/product/pangu"
[ -d "$PG/system" ] || die "product/pangu/system not found"
cp -a "$PG/system/." "$SR/"
info "product/pangu/system -> system: $(find "$PG/system" -type f | wc -l) files"
rm -rf "$PG"

# ---------------------------------------------------------------- 3
log "3/6 device changes"
# Java sources in config/{display,perf,touch}/src
GEN="$OUT/gen"; rm -rf "$GEN"
for d in display perf touch; do java2smali "$CONF/$d" "$GEN/$d" || die "config/$d/src: compile failed"; done
# Performance / UniperfClient replace methods of existing classes; the method headers come from the base ROM.
orig_class "$SR/framework/QPerformance.jar" com/qualcomm/qti/Performance "$GEN/orig"
orig_class "$S/system_ext/framework/miui-services.jar" com/xiaomi/uniperf/UniperfClient "$GEN/orig"
$PY "$CONF/perf/merge_methods.py" "$GEN/perf/com/qualcomm/qti/Performance.smali" "$GEN/orig/com/qualcomm/qti/Performance.smali" \
  "$GEN/perf/Performance.methods.smali" 'QPerformance.jar com.qualcomm.qti.Performance: perf* go to PortPerfHook' >/dev/null
$PY "$CONF/perf/merge_methods.py" "$GEN/perf/com/xiaomi/uniperf/UniperfClient.smali" "$GEN/orig/com/xiaomi/uniperf/UniperfClient.smali" \
  "$GEN/perf/UniperfClient.methods.smali" 'miui-services.jar com.xiaomi.uniperf.UniperfClient: calls go to PortPerfHint' >/dev/null
# PortPerfHook goes on the boot classpath: mark its members whitelist for hiddenapi
sed -i -E 's/^(\.(method|field) ([a-z-]+ )*)/\1whitelist /' "$GEN/perf/com/qualcomm/qti/PortPerfHook.smali"
info "config/{display,perf,touch}/src compiled"

F="$S/product/etc/device_features"
if [ ! -f "$F/$PX_DEVICE.xml" ]; then
  [ -f "$F/$HY_DEVICE.xml" ] || die "device_features/$HY_DEVICE.xml not found"
  cp -a "$F/$HY_DEVICE.xml" "$F/$PX_DEVICE.xml"
fi
if [ "$HZ90" -eq 1 ]; then
  $PY "$TOOLS/features_fps.py" "$F/$PX_DEVICE.xml" "$F/$PX_DEVICE.xml" 90 60 || die "features_fps failed"
  info "$PX_DEVICE.xml: refresh rates 90/60"
fi

# The Pixel vendor starts class animation at late-fs, before all APEXes are active; Xiaomi's surfaceflinger
# links against the tethering APEX and keeps failing there. Start it with class core only.
SFRC="$SR/etc/init/surfaceflinger.rc"
grep -q '^    class core animation$' "$SFRC" || die "unexpected class line in surfaceflinger.rc"
sed 's/^    class core animation$/    class core/' "$SFRC" > "$SFRC.tmp"; cat "$SFRC.tmp" > "$SFRC"; rm -f "$SFRC.tmp"

# Buffers allocated by Xiaomi's SurfaceFlinger carry the Qualcomm UBWC usage bit (1<<28), which Mali gralloc
# rejects and surfaceflinger aborts. Each site is "movz wN, #imm; movk wN, #0x1000, lsl #16"; NOP the movk.
# Offsets are for libsurfaceflinger.so of OS4.0.29.0 (found with movk patterns).
for pr in 0x445fd0:0900a272 0x599b20:0200a272 0x608044:0b00a272 0x610a80:0800a272 0x611b84:0500a272 0x612b74:0800a272 0x674b94:0500a272; do
  $PY "$TOOLS/binpatch.py" "$S/system_ext/lib64/libsurfaceflinger.so" "${pr%%:*}" "${pr#*:}" 1f2003d5 >/dev/null \
    || die "libsurfaceflinger.so patch failed (different base version?)"
done
# MiSurfaceFlingerImpl::setPrivacyMode calls a Xiaomi HAL every frame and logs twice per failure.
# Keep paciasp, replace the next two instructions with autiasp; ret.
$PY "$TOOLS/binpatch.py" "$S/system_ext/lib64/libmisurfaceflinger.so" 0x634c8 ff8301d1fd7b02a9 bf2303d5c0035fd6 >/dev/null \
  || die "libmisurfaceflinger.so patch failed (different base version?)"
# Liquid glass: the corner SDF shader's early return "if(x >= 0.85) return 1.0;" in curve() is miscomputed
# on Mali, leaving a hole in the middle of glass surfaces. Rewrite curve() without it (same length).
$PY "$TOOLS/glass_fix_gen.py" "$SR/lib64/libhwui.so" "$SR/lib64/libhwui.so" >/dev/null || die "libhwui.so patch failed (different base version?)"
info "surfaceflinger.rc class core; libsurfaceflinger UBWC bits; setPrivacyMode no-op; libhwui glass shader"

# DevicesAndroidOverlay (priority above the Pixel vendor overlay) sets madrid's 172px corner radius.
T="$(mktemp -d)"; OV="$S/product/overlay/DevicesAndroidOverlay.apk"
$PY "$TOOLS/apk_patch.py" "$OV" "$T/u.apk" --dimen rounded_corner_radius=47px \
  --dimen rounded_corner_radius_top=47px --dimen rounded_corner_radius_bottom=48px || die "DevicesAndroidOverlay patch failed"
sign_to "$T/u.apk" "$OV"; rm -rf "$T"

# NFC: XMNfcNci only starts with /dev/nq-nci present (Pixel has /dev/st21nfc, port_nfc.rc links it);
# its mi_nfc service needs a service_contexts entry; libnfc-nci.conf comes from the Pixel product.
inst 0644 "$CONF/nfc/port_nfc.rc" "$S/system_ext/etc/init/port_nfc.rc"
append "$S/system_ext/etc/selinux/system_ext_service_contexts" 'mi_nfc                                         u:object_r:nfc_service:s0'
[ -f "$PX/parts/product/etc/libnfc-nci.conf" ] || die "Pixel product has no etc/libnfc-nci.conf"
cp -a "$PX/parts/product/etc/libnfc-nci.conf" "$S/product/etc/libnfc-nci.conf"
info "NFC: port_nfc.rc, mi_nfc service context, Pixel libnfc-nci.conf"

# Face unlock: madrid's mifaced needs Xiaomi's TEE; use facehal-rs built for system_ext.
FH="$CONF/facehal/prebuilt"
if [ -x "$FH/android.hardware.biometrics.face-service.facehal" ]; then
  [ ! -f "$FH/SHA256SUMS" ] || (cd "$FH" && sha256sum -c --quiet SHA256SUMS) || die "config/facehal/prebuilt does not match SHA256SUMS"
  [ -d "$S/system_ext/bin/hw" ] || { install -d -m 0755 -o root -g root "$S/system_ext/bin/hw"; setlabel "$S/system_ext/bin/hw"; }
  B="$S/system_ext/bin/hw/android.hardware.biometrics.face-service.facehal"
  install -m 0755 -o root -g root "$FH/android.hardware.biometrics.face-service.facehal" "$B"; label "$B" port_facehal_exec
  inst 0644 "$CONF/facehal/port_facehal.rc" "$S/system_ext/etc/init/port_facehal.rc"
  inst 0644 "$CONF/facehal/port_facehal.xml" "$S/system_ext/etc/vintf/manifest/port_facehal.xml"
  # feature declaration from madrid's vendor; FaceService does not start without it
  FX="$HY/parts/vendor/etc/permissions/android.hardware.biometrics.face.xml"
  [ -f "$FX" ] || die "madrid vendor has no etc/permissions/android.hardware.biometrics.face.xml"
  inst 0644 "$FX" "$S/system_ext/etc/permissions/android.hardware.biometrics.face.xml"
  install -d -m 0755 -o root -g root "$S/system_ext/lib64/facehal"; label "$S/system_ext/lib64/facehal" system_lib_file
  for f in "$FH"/lib64/*.so; do
    install -m 0644 -o root -g root "$f" "$S/system_ext/lib64/facehal/"; label "$S/system_ext/lib64/facehal/$(basename "$f")" system_lib_file
  done
  append "$S/system_ext/etc/selinux/system_ext_file_contexts" \
    '/(system_ext|system/system_ext)/bin/hw/android\.hardware\.biometrics\.face-service\.facehal  u:object_r:port_facehal_exec:s0' \
    '/data/system_de/[0-9]+/facedata(/.*)?  u:object_r:port_facehal_data_file:s0'
  add_cil "$CONF/facehal/sepolicy.cil"
  info "face: facehal-rs installed"
else
  info "face: no config/facehal/prebuilt, skipped"
fi

# services.jar
J="$SR/framework/services.jar"
# Under-display fingerprint: FingerprintService.setUdfpsOverlayController is stubbed; restore the AOSP body.
bash "$TOOLS/dex_method.sh" "$J" 'com/android/server/biometrics/sensors/fingerprint/FingerprintService$1' \
  "$CONF/fingerprint/fp_setUdfpsOverlayController.smali" || die "services.jar patch failed"
add_cil "$CONF/fingerprint/sepolicy.cil"
# Double-tap to wake / long-press fingerprint on AOD via Pixel wake sensors (host class picked for dex method headroom).
jar_smali "$J" com/android/server/wm/ActionChain "$CONF/gestures/PortGestures.smali" "$CONF/gestures/PortGestures\$L.smali"
# Power-saving / performance modes -> sys.port.perfmode -> port_perf.rc -> Pixel powerhint; PortPerfHint receives
# Uniperf / Qualcomm Performance calls. Sources in config/perf/src.
jar_smali "$J" com/android/server/power/PowerManagerService \
  "$CONF/perf/PortPerfBridge.smali" "$CONF/perf/PortPerfScreen.smali" "$GEN/perf/com/android/server/power"/PortPerfHint*.smali \
  "$CONF/perf/onBootPhase.insert"
chown root:root "$J"; chmod 0644 "$J"; setlabel "$J"
# QPerformance.jar (boot classpath): perf* methods go to PortPerfHook instead of looking up perf2.
J="$SR/framework/QPerformance.jar"
jar_smali "$J" com/qualcomm/qti/Performance "$GEN/perf/com/qualcomm/qti/PortPerfHook.smali" "$GEN/perf/Performance.methods.smali"
chown root:root "$J"; chmod 0644 "$J"; setlabel "$J"
inst 0644 "$CONF/perf/port_perf.rc" "$S/system_ext/etc/init/port_perf.rc"
info "services.jar: udfps controller, PortGestures, PortPerf*; QPerformance.jar; port_perf.rc"

APK="$S/system_ext/priv-app/MiuiSystemUI/MiuiSystemUI.apk"
# The gxzw_touch window (flags 0x1800708) sits above UdfpsController and eats touches: add FLAG_NOT_TOUCHABLE.
$PY "$TOOLS/apk_dex_inplace.py" "$APK" classes3.dex 141c08078001 141c18078001 | sed 's/^/    /'
[ "${PIPESTATUS[0]}" -eq 0 ] || die "MiuiSystemUI patch failed (different version?)"
# PortAodLongPress: AOD long press on the fingerprint area, tap shows the icon, pick up to wake.
smali_graft "$APK" "$CONF/aod/systemui.patch"
# Settings: show "lift to wake" for Google's pick_up_gesture sensor.
APK="$S/system_ext/priv-app/Settings/Settings.apk"
smali_graft "$APK" "$CONF/aod/settings.patch"
rm -rf "$S/system_ext/priv-app/Settings/oat"
info "MiuiSystemUI: udfps touch window, PortAodLongPress; Settings: lift to wake"

# miui-services.jar
J="$S/system_ext/framework/miui-services.jar"
# Display features (color scheme, temperature, reading mode, paper mode) go to PortDisplayBridge, which maps them
# to Android color modes and DTM matrices instead of Xiaomi's IDisplayFeature HAL. Sources in config/display/src.
jar_smali "$J" 'com/android/server/display/DisplayFeatureManagerService$DisplayFeatureManagerWrapper' \
  "$GEN/display/com/android/server/display"/PortDisplayBridge*.smali "$CONF/display/Wrapper.methods.smali"
jar_smali "$J" com/android/server/display/DisplayFeatureManagerService "$CONF/display/DisplayFeatureManagerService.methods.smali"
# UniperfClient: no IUniperf lookup; calls are handed to PortPerfHint.
jar_smali "$J" com/xiaomi/uniperf/UniperfClient "$GEN/perf/UniperfClient.methods.smali"
# Touch: PortTouchFeature registers vendor.xiaomi.hw.touchfeature.ITouchFeature/default; PortTouchContext sends
# orientation and glove (screen protector) mode to twoshay. Sources in config/touch/src.
jar_smali "$J" com/android/server/SystemServerImpl \
  "$GEN/touch/com/android/server/input"/PortTouch*.smali \
  "$CONF/touch/addExtraServices.insert"
setlabel "$J"
append "$S/system_ext/etc/selinux/system_ext_service_contexts" 'vendor.xiaomi.hw.touchfeature.ITouchFeature/default u:object_r:port_touch_service:s0'
inst 0644 "$CONF/touch/port_touch.xml" "$S/system_ext/etc/vintf/manifest/port_touch.xml"
add_cil "$CONF/touch/sepolicy.cil"
append "$S/system_ext/etc/build.prop" '# port: glove mode switch' 'ro.vendor.touchfeature.glovemode=true'
info "miui-services.jar: PortDisplayBridge, UniperfClient, PortTouchFeature/Context"

# Charge protection and battery health: IMiCharge methods go to PortMiCharge (persist.sys.port.*, applied by
# port_charge.rc; cycle count and health read from Pixel battery nodes).
J="$S/system_ext/framework/miui-framework.jar"
jar_smali "$J" miui/util/IMiCharge "$CONF/micharge/PortMiCharge.smali" "$CONF/micharge/IMiCharge.methods.smali"
setlabel "$J"
inst 0644 "$CONF/micharge/port_charge.rc" "$S/system_ext/etc/init/port_charge.rc"
add_cil "$CONF/micharge/sepolicy.cil"
# Boot classpath jars changed: drop the precompiled boot image, odrefresh rebuilds it in /data on first boot
# (it checks presence, not checksums; a stale image makes ART fall back to interpreting the framework).
rm -f "$SR"/framework/arm/boot* "$SR"/framework/arm64/boot*
info "miui-framework.jar: PortMiCharge; precompiled boot image removed"

APK="$S/product/priv-app/MiuiCamera/MiuiCamera.apk"
if [ -f "$APK" ]; then
  # Device check: unknown models (no com.mi.device.<model>) count as "version error"; take the generic path.
  $PY "$TOOLS/apk_dex_inplace.py" "$APK" classes3.dex 7100f11000000a0138010e00 7100f11000000a0129000e00 \
    || die "MiuiCamera patch failed (different version?)"
  # Session modes >= 0x8000 are Xiaomi/Qualcomm private and rejected by the Pixel camera HAL: map them to 0.
  #   shr-int/lit8 v0, p1, 15 ; if-eqz v0, +3 ; const/4 p1, 0
  $PY "$TOOLS/apk_dex_inplace.py" "$APK" classes4.dex 1a00575e712049150300 e000020f380003001202 \
    || die "MiuiCamera session mode patch failed (different version?)"
  # 0.6x ultra wide button
  smali_graft "$APK" "$CONF/camera/miuicamera.patch"
  info "MiuiCamera: generic device config, session mode, 0.6x"
fi

# Voice wake: the DSP only accepts Google models, so keep the second-stage keyword engine listening.
APK="$S/product/app/VoiceTrigger/VoiceTrigger.apk"
[ ! -f "$APK" ] || { smali_graft "$APK" "$CONF/voicetrigger/voicetrigger.patch"; info "VoiceTrigger: software always-on listening"; }

[ ! -f "$S/product/etc/device_info.json" ] || cat "$BASE/device_info.json" > "$S/product/etc/device_info.json"

# Telephony: Pixel components (Shannon IMS/QNS, Iwlan, CarrierSettings, eSIM) and overlays pointing at them.
PX_SR0="$(sysroot "$PX/parts/system")"
n=0
for f in esim ims wfc carrier attention; do
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo $line)"
    [ -n "$line" ] || continue
    p="${line%%/*}"; sub="${line#*/}"
    case "$p" in
      system) src="$PX_SR0/$sub"; dst="$SR/$sub" ;;
      *)      src="$PX/parts/$line"; dst="$S/$line" ;;
    esac
    [ -e "$src" ] || die "Pixel has no $line (config/$f/pixel_add.txt)"
    mkdir_l "$(dirname "$dst")"
    cp -a --remove-destination "$src" "$(dirname "$dst")/"
    n=$((n+1))
  done < "$CONF/$f/pixel_add.txt"
done
inst 0644 "$BASE/privapp-permissions-port.xml" "$S/product/etc/permissions/privapp-permissions-port.xml"
inst 0644 "$BASE/sysconfig-port.xml" "$S/system_ext/etc/sysconfig/sysconfig-port.xml"
inst 0644 "$BASE/default-permissions-port.xml" "$S/product/etc/default-permissions/default-permissions-port.xml"
sc="$S/system_ext/etc/selinux/system_ext_seapp_contexts"
append "$sc" 'user=_app isPrivApp=true name=com.google.android.euicc domain=euicc_app type=privapp_data_file levelFrom=user'
grep -E 'name=(com\.shannon\.|\.ShannonImsService)' "$PX/parts/system_ext/etc/selinux/system_ext_seapp_contexts" >> "$sc" \
  || die "no Shannon entries in the Pixel system_ext_seapp_contexts"
add_cil "$CONF/esim/sepolicy.cil"
add_cil "$CONF/ims/sepolicy.cil"
info "pixel_add.txt: $n entries; permissions, sysconfig, seapp_contexts, sepolicy"

T="$(mktemp -d)"
OV="$S/product/overlay/TelephonyResCommon_Sys.apk"; [ -f "$OV" ] || die "$OV not found"
$PY "$TOOLS/arsc_replace.py" "$OV" "$T/u.apk" org.codeaurora.ims com.shannon.imsservice || die "TelephonyResCommon_Sys patch failed"
sign_to "$T/u.apk" "$OV"
OV="$S/product/overlay/FrameworksResCommon_Sys.apk"; [ -f "$OV" ] || die "$OV not found"
$PY "$TOOLS/arsc_strings.py" "$OV" "$T/u.apk" \
  config_qualified_networks_service_package=com.shannon.qualifiednetworksservice \
  config_wlan_data_service_package=com.google.android.iwlan \
  config_wlan_network_service_package=com.google.android.iwlan | sed 's/^/    /' || die "FrameworksResCommon_Sys patch failed"
sign_to "$T/u.apk" "$OV"
# Screen attention: Xiaomi AON needs an always-on camera service; use Android System Intelligence instead.
OV="$S/product/overlay/AospFrameworkResOverlay.apk"; [ -f "$OV" ] || die "$OV not found"
$PY "$TOOLS/arsc_strings.py" "$OV" "$T/u.apk" \
  config_defaultAttentionService=com.google.android.as/com.google.android.apps.miphone.aiai.attention.service.AiAiAttentionService \
  | sed 's/^/    /' || die "AospFrameworkResOverlay patch failed"
sign_to "$T/u.apk" "$OV"
FWRES="$SR/framework/framework-res.apk"
bash "$CONF/carrier/build_rro.sh" "$FWRES" "$KS" "$T/rro.apk" || die "carrier RRO build failed"
inst 0644 "$T/rro.apk" "$S/product/overlay/PortTeleServiceOverlay.apk"
# Find Device stub: the real app is removed, but Xiaomi Account crashes without FindDeviceStatusManagerService.
bash "$CONF/finddevice/build_stub.sh" "$FWRES" "$KS" "$T/fd.apk" || die "Find Device stub build failed"
inst 0644 "$T/fd.apk" "$S/product/app/PortFindDevice/PortFindDevice.apk"
# Xiaomi eSIM manager; its EuiccService priority (101) beats Google's (100), which stays as fallback.
if [ -f "$CONF/esim/EsimLPA.apk" ]; then
  inst 0644 "$CONF/esim/EsimLPA.apk" "$S/product/priv-app/EsimLPA/EsimLPA.apk"
  info "EsimLPA installed"
else
  info "no config/esim/EsimLPA.apk, skipped"
fi
# Iwlan without the system sharedUserId, re-signed
APK="$PX/parts/system_ext/priv-app/Iwlan/Iwlan.apk"; [ -f "$APK" ] || die "Pixel has no system_ext/priv-app/Iwlan"
$PY "$TOOLS/axml_drop_attr.py" "$APK" "$T/u.apk" manifest 0x0101000b | sed 's/^/    /' || die "Iwlan manifest patch failed"
mkdir_l "$S/system_ext/priv-app/Iwlan"
sign_to "$T/u.apk" "$S/system_ext/priv-app/Iwlan/Iwlan.apk"
rm -rf "$T"
inst 0644 "$CONF/wfc/port_iwlan.rc" "$S/system_ext/etc/init/port_iwlan.rc"
inst 0644 "$CONF/esim/port_esim.rc" "$S/system_ext/etc/init/port_esim.rc"
inst 0755 "$CONF/esim/port_esim.sh" "$S/system_ext/bin/port_esim.sh"
info "telephony overlays, carrier RRO, Find Device stub, Iwlan"

# ---------------------------------------------------------------- 4
log "4/6 properties"
for bp in "$SR/build.prop" "$S/system_ext/etc/build.prop" "$S/product/etc/build.prop"; do
  [ ! -f "$bp" ] || $PY "$TOOLS/props.py" drop "$bp" "$BASE/drop.prop"
done
for f in "$CONF"/*/product.prop; do
  $PY "$TOOLS/props.py" merge "$S/product/etc/build.prop" "$f" "port: ${f#$HERE/}"
done

# ---------------------------------------------------------------- 5
log "5/6 SELinux"
add_cil "$BASE/sepolicy.cil"
n=0
while read -r fs path; do
  [ -n "${fs:-}" ] && [ "${fs#\#}" = "$fs" ] || continue
  for cil in "$(SEPOL_EXT)" "$S/product/etc/selinux/product_sepolicy.cil" "$SR"/etc/selinux/plat_sepolicy_genfs_*.cil; do
    [ -f "$cil" ] || continue
    c=$(grep -cF "(genfscon $fs \"$path\" " "$cil" || true)
    [ "$c" -gt 0 ] || continue
    grep -vF "(genfscon $fs \"$path\" " "$cil" > "$cil.tmp"; cat "$cil.tmp" > "$cil"; rm -f "$cil.tmp"
    n=$((n + c))
  done
done < "$BASE/genfs_drop.txt"
info "genfscon entries conflicting with the Pixel vendor removed: $n"
$PY "$TOOLS/sepolicy_check.py" "$SR" "$S/system_ext" "$S/product" "$PX/parts/vendor" || die "SELinux policy does not compile"

# ---------------------------------------------------------------- 6
log "6/6 erofs"
for p in "${PARTS[@]}"; do
  $PY "$TOOLS/dump_meta.py" "$S/$p" "$OUT/meta/$p.stage.tsv" | sed 's/^/  /'
  unl=$(awk -F'\t' 'NR>1 && $6=="" {print $1}' "$OUT/meta/$p.stage.tsv" | head -5)
  [ -z "$unl" ] || { echo "$unl" | sed 's/^/      unlabelled: /'; die "$p has files without an SELinux label"; }
  # services.jar and QPerformance.jar are stored uncompressed (see config/base/erofs.hints): the patched services.jar
  # compressed with lz4hc hard-reboots the phone early in boot.
  mkfs.erofs -zlz4hc --compress-hints="$BASE/erofs.hints" --quiet "$IMG/$p.img" "$S/$p"
  info "$p.img  $(du -h --apparent-size "$IMG/$p.img" | cut -f1)"
done
if [ "$VERIFY" -eq 1 ]; then
  for p in "${PARTS[@]}"; do
    t="$OUT/verify_$p"; rm -rf "$t" "$t.caps"; mkdir -p "$t" "$t.caps"
    fsck.erofs --extract="$t" --xattrs --preserve --overwrite "$IMG/$p.img" >/dev/null
    fsck.erofs --extract="$t.caps" --xattrs --no-preserve-owner --overwrite "$IMG/$p.img" >/dev/null
    $PY "$TOOLS/copy_caps.py" "$t.caps" "$t" >/dev/null
    $PY "$TOOLS/dump_meta.py" "$t" "$OUT/meta/$p.image.tsv" >/dev/null
    echo "    $p.img metadata check:"
    $PY "$TOOLS/compare_meta.py" "$OUT/meta/$p.stage.tsv" "$OUT/meta/$p.image.tsv" | sed 's/^/  /' || die "$p.img metadata differs from stage"
    rm -rf "$t" "$t.caps"
  done
fi
rm -rf "$S" "$TMPDIR"
(cd "$IMG" && sha256sum *.img)
log "done: $IMG"
