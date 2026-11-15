#!/bin/bash
# Build the telephony overlay: build_rro.sh <framework-res.apk> <keystore> <out apk>
set -e
H="$(cd "$(dirname "$0")" && pwd)"
FR="$1"; KS="$2"; OUT="$3"
A2="$H/../../tools/bin/aapt2"; [ -x "$A2" ] || A2=aapt2
T="$(mktemp -d)"
"$A2" compile --dir "$H/rro/res" -o "$T/res.zip"
"$A2" link -I "$FR" --manifest "$H/rro/AndroidManifest.xml" -o "$T/u.apk" "$T/res.zip"
zipalign -p -f 4 "$T/u.apk" "$T/a.apk"
apksigner sign --ks "$KS" --ks-pass pass:android --key-pass pass:android --out "$OUT" "$T/a.apk"
rm -rf "$T" "$OUT.idsig"
