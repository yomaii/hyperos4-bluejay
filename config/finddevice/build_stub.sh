#!/bin/bash
# Build the Find Device stub: build_stub.sh <framework-res.apk> <keystore> <out apk>
set -e
H="$(cd "$(dirname "$0")" && pwd)"
FR="$1"; KS="$2"; OUT="$3"
A2="$H/../../tools/bin/aapt2"; [ -x "$A2" ] || A2=aapt2
T="$(mktemp -d)"
"$A2" link -I "$FR" --manifest "$H/AndroidManifest.xml" -o "$T/u.apk"
smali a "$H/smali" --api 28 -o "$T/classes.dex"
python3 -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1],"a",zipfile.ZIP_DEFLATED).write(sys.argv[2],"classes.dex")' "$T/u.apk" "$T/classes.dex"
zipalign -p -f 4 "$T/u.apk" "$T/a.apk"
apksigner sign --ks "$KS" --ks-pass pass:android --key-pass pass:android --out "$OUT" "$T/a.apk"
rm -rf "$T" "$OUT.idsig"
