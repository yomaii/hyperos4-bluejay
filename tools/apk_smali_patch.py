#!/usr/bin/env python3
"""Patch smali lines inside the dex files of an apk/jar, reassemble, write a new unsigned apk.

  apk_smali_patch.py <in.apk> <out.apk> <patch file>

Patch file (UTF-8, '#' lines and blank lines ignored):

  @ classes6.dex Cg/i0.smali            which dex, which smali file (path as baksmali writes it)
  method .method public static i()      the method whose header line starts with this text
  - if-eqz v1, :cond_50                 old lines, consecutive, compared after stripping spaces
  + goto :cond_50                       new lines (none = delete the old lines)

  @ classes.dex a/B.smali
  file B.smali                          replace the whole smali file (path relative to the patch file);
                                        if the dex has no such class, it is added

Each '-' block must match exactly once inside its method, otherwise nothing is written.
Every dex that is patched is disassembled with baksmali and reassembled with smali at the API
level that gives back the same dex version. Other zip entries keep their order and compression.
An APK signing block and META-INF signature files are dropped: zipalign + apksigner afterwards.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

API_FOR_VERSION = {b'035': 23, b'037': 25, b'038': 27, b'039': 28}


def parse(path):
    patches, cur = [], None
    for n, raw in enumerate(open(path, encoding='utf-8'), 1):
        line = raw.rstrip('\n')
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        if s.startswith('@ '):
            dex, smali = s[2:].split()
            cur = {'dex': dex, 'smali': smali, 'method': None, 'old': [], 'new': [], 'line': n,
                   'file': None}
            patches.append(cur)
        elif cur is None:
            sys.exit(f'{path}:{n}: expected "@ <dex> <smali>" first')
        elif s.startswith('file '):
            cur['file'] = os.path.join(os.path.dirname(os.path.abspath(path)), s[len('file '):].strip())
            if not os.path.isfile(cur['file']):
                sys.exit(f'{path}:{n}: no such file {cur["file"]}')
        elif s.startswith('method '):
            cur['method'] = s[len('method '):].strip()
        elif s.startswith('- '):
            if cur['new']:
                sys.exit(f'{path}:{n}: "-" after "+" in one patch')
            cur['old'].append(s[2:].strip())
        elif s.startswith('+ ') or s == '+':
            cur['new'].append(line.split('+', 1)[1][1:] if s != '+' else '')
        else:
            sys.exit(f'{path}:{n}: cannot parse: {s}')
    for p in patches:
        if p['file']:
            if p['method'] or p['old'] or p['new']:
                sys.exit(f'{path}:{p["line"]}: "file" cannot be mixed with method/-/+ lines')
            continue
        if not p['method'] or not p['old']:
            sys.exit(f'{path}:{p["line"]}: patch needs a method and at least one "-" line')
    return patches


def apply(smali_path, p):
    if p['file']:
        shutil.copyfile(p['file'], smali_path)
        print(f'apk_smali_patch: {p["dex"]} {p["smali"]}: replaced with {os.path.basename(p["file"])}')
        return
    lines = open(smali_path, encoding='utf-8').read().split('\n')
    starts = [i for i, l in enumerate(lines) if l.startswith(p['method'])]
    if len(starts) != 1:
        sys.exit(f'{p["smali"]}: method "{p["method"]}" found {len(starts)} times, expected 1')
    s = starts[0]
    e = next(i for i in range(s, len(lines)) if lines[i].startswith('.end method'))
    # Compare only real lines: baksmali puts ".line N" and blank lines between instructions
    sig = [i for i in range(s, e) if lines[i].strip() and not lines[i].strip().startswith('.line ')]
    k = len(p['old'])
    hits = [x for x in range(len(sig) - k + 1)
            if [lines[sig[x + j]].strip() for j in range(k)] == p['old']]
    if len(hits) != 1:
        sys.exit(f'{p["smali"]} {p["method"]}: old lines found {len(hits)} times, expected 1:\n  '
                 + '\n  '.join(p['old']))
    i, last = sig[hits[0]], sig[hits[0] + k - 1]
    indent = re.match(r'\s*', lines[i]).group(0)
    new = [(indent + l.strip()) if l.strip() else '' for l in p['new']]
    lines[i:last + 1] = new
    open(smali_path, 'w', encoding='utf-8').write('\n'.join(lines))
    print(f'apk_smali_patch: {p["dex"]} {p["smali"]} {p["method"]}: {k} line(s) -> {len(new)}')


def main(src, out, patch_file):
    patches = parse(patch_file)
    tmp = tempfile.mkdtemp()
    try:
        new_dex = {}
        with zipfile.ZipFile(src) as zi:
            for dex in sorted({p['dex'] for p in patches}):
                data = zi.read(dex)
                ver = data[4:7]
                if ver not in API_FOR_VERSION:
                    sys.exit(f'apk_smali_patch: {dex} has unsupported dex version {ver!r}')
                d = os.path.join(tmp, dex)
                open(d, 'wb').write(data)
                sd = os.path.join(tmp, dex + '.smali')
                subprocess.run(['baksmali', 'd', d, '-o', sd], check=True, stdout=subprocess.DEVNULL)
                for p in patches:
                    if p['dex'] == dex:
                        f = os.path.join(sd, p['smali'])
                        if not os.path.isfile(f):
                            if not p['file']:
                                sys.exit(f'apk_smali_patch: {dex} has no {p["smali"]}')
                            # "file" names a class not in the dex: add it
                            os.makedirs(os.path.dirname(f), exist_ok=True)
                            print(f'apk_smali_patch: {dex} {p["smali"]}: new class')
                        apply(f, p)
                nd = os.path.join(tmp, dex + '.new')
                subprocess.run(['smali', 'a', '--api', str(API_FOR_VERSION[ver]), sd, '-o', nd],
                               check=True, stdout=subprocess.DEVNULL)
                nb = open(nd, 'rb').read()
                if nb[4:7] != ver:
                    sys.exit(f'apk_smali_patch: {dex} came back as version {nb[4:7]!r}, was {ver!r}')
                new_dex[dex] = nb
            sig = re.compile(r'^META-INF/[^/]+\.(SF|RSA|DSA|EC|MF)$')
            with zipfile.ZipFile(out, 'w', allowZip64=True) as zo:
                for it in zi.infolist():
                    if sig.match(it.filename):
                        continue
                    data = new_dex.get(it.filename) or zi.read(it)
                    zo.writestr(it, data, compress_type=it.compress_type)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
