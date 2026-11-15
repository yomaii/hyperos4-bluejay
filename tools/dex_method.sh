#!/usr/bin/env bash
# Replace one method of a class in a jar (multi-dex is fine) with the one in a patch file.
#
#   dex_method.sh <jar> <class, e.g. com/foo/Bar$1> <patch .smali>
#
# The patch holds one complete method; the method with the same .method line must exist exactly once.
# Only the dex containing the class is reassembled (smali --api 28).
set -euo pipefail
JAR="$(realpath "$1")" CLS="$2" PATCH="$(realpath "$3")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

dex=""
for d in $(unzip -Z1 "$JAR" | grep -E '^classes[0-9]*\.dex$'); do
  unzip -q -o "$JAR" "$d" -d "$T"
  if baksmali list classes "$T/$d" | grep -qxF "L$CLS;"; then dex="$d"; break; fi
  rm -f "$T/$d"
done
[ -n "$dex" ] || { echo "dex_method: class $CLS not found in $JAR" >&2; exit 1; }

baksmali d "$T/$dex" -o "$T/s" >/dev/null
F="$T/s/$CLS.smali"
[ -f "$F" ] || { echo "dex_method: no $CLS.smali after baksmali" >&2; exit 1; }

python3 -I - "$F" "$PATCH" <<'PY'
import sys
f, patch = sys.argv[1:]
P = open(patch).read().strip('\n').split('\n')
head = next((l.strip() for l in P if l.strip().startswith('.method')), None)
if head is None or P[-1].strip() != '.end method':
    sys.exit(f'dex_method: {patch} is not a single complete method')
L = open(f).read().split('\n')
hits = [i for i, l in enumerate(L) if l.strip() == head]
if len(hits) != 1:
    sys.exit(f'dex_method: "{head}" found {len(hits)} times, expected 1')
s = hits[0]
e = next(i for i in range(s, len(L)) if L[i].startswith('.end method'))
L[s:e + 1] = [l for l in P if not l.lstrip().startswith('#')]
open(f, 'w').write('\n'.join(L))
PY

smali a --api 28 "$T/s" -o "$T/new.dex" >/dev/null
python3 -I - "$JAR" "$dex" "$T/new.dex" "$T/out.jar" <<'PY'
import sys, zipfile
src, name, dex, out = sys.argv[1:]
data = open(dex, 'rb').read()
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(out, 'w') as zo:
    for it in zi.infolist():
        zo.writestr(it, data if it.filename == name else zi.read(it), compress_type=it.compress_type)
PY
zipalign -p -f 4 "$T/out.jar" "$T/aligned.jar"
cat "$T/aligned.jar" > "$JAR"   # in place, keeps owner, mode and SELinux label
echo "dex_method: $(basename "$JAR") $dex $CLS: replaced $(grep -m1 '^\s*\.method' "$PATCH" | sed 's/^ *//')"
