#!/usr/bin/env python3
"""Add classes to / replace methods in the dex of a jar, in place.

  jar_smali.py <jar> <host class, e.g. miui/util/IMiCharge> <file.smali>...

Each file is either
  - a whole class (first real line is ".class ..."): written into the dex that holds the host class,
    at the path its .class line gives (a new class, or a full replacement), or
  - one or more complete methods (".method ..." to ".end method") of the host class: each replaces
    the method whose header line is identical (after stripping spaces); it must occur exactly once, or
  - an insertion into one method of the host class:
        .in-method <method header line>
        .after <anchor line>
        <lines to insert after the anchor>
    the header must occur once in the class and the anchor once inside that method (both compared
    after stripping spaces); the rest of the method stays as it is.

Only the dex that holds the host class is reassembled (smali at an API level that keeps the dex
version and hidden-API flags). Other zip entries keep their order and compression; the jar is
zipaligned and written back over the original file, so owner, mode and SELinux label stay.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

# Hidden-API flags (baksmali writes "blacklist" etc.) need smali --api 29 or later.
API_FOR_VERSION = {b'035': 29, b'037': 29, b'038': 29, b'039': 30}


def real_lines(text):
    return [l for l in text.split('\n') if l.strip() and not l.strip().startswith('#')]


def methods_of(text):
    out, cur = [], None
    for l in text.split('\n'):
        s = l.strip()
        if s.startswith('.method '):
            cur = [l]
        elif cur is not None:
            if not s.startswith('#'):
                cur.append(l)
            if s == '.end method':
                out.append(cur)
                cur = None
    if cur is not None:
        sys.exit('jar_smali: unterminated .method')
    return out


def replace_methods(cls_file, patch_name, methods):
    L = open(cls_file, encoding='utf-8').read().split('\n')
    for m in methods:
        head = m[0].strip()
        hits = [i for i, l in enumerate(L) if l.strip() == head]
        if len(hits) != 1:
            sys.exit(f'jar_smali: {patch_name}: "{head}" found {len(hits)} times in host class, expected 1')
        s = hits[0]
        e = next(i for i in range(s, len(L)) if L[i].startswith('.end method'))
        L[s:e + 1] = m
        print(f'jar_smali:   replaced {head}')
    open(cls_file, 'w', encoding='utf-8').write('\n'.join(L))


def insert_lines(cls_file, patch_name, lines):
    head = lines[0].strip()[len('.in-method'):].strip()
    if not lines[1].strip().startswith('.after '):
        sys.exit(f'jar_smali: {patch_name}: second line must be ".after <anchor>"')
    anchor = lines[1].strip()[len('.after'):].strip()
    body = lines[2:]
    if not body:
        sys.exit(f'jar_smali: {patch_name}: nothing to insert')
    L = open(cls_file, encoding='utf-8').read().split('\n')
    hits = [i for i, l in enumerate(L) if l.strip() == head]
    if len(hits) != 1:
        sys.exit(f'jar_smali: {patch_name}: "{head}" found {len(hits)} times in host class, expected 1')
    s = hits[0]
    e = next(i for i in range(s, len(L)) if L[i].startswith('.end method'))
    at = [i for i in range(s, e) if L[i].strip() == anchor]
    if len(at) != 1:
        sys.exit(f'jar_smali: {patch_name}: anchor "{anchor}" found {len(at)} times in {head}, expected 1')
    L[at[0] + 1:at[0] + 1] = [''] + body
    print(f'jar_smali:   inserted {len(body)} lines into {head}')
    open(cls_file, 'w', encoding='utf-8').write('\n'.join(L))


def main(jar, host, files):
    tmp = tempfile.mkdtemp()
    try:
        with zipfile.ZipFile(jar) as zi:
            dex = None
            for name in zi.namelist():
                if re.fullmatch(r'classes\d*\.dex', name):
                    p = os.path.join(tmp, name)
                    open(p, 'wb').write(zi.read(name))
                    r = subprocess.run(['baksmali', 'list', 'classes', p], check=True,
                                       capture_output=True, text=True)
                    if f'L{host};' in r.stdout.split():
                        dex = name
                        break
            if dex is None:
                sys.exit(f'jar_smali: {jar} has no class {host}')
            data = open(os.path.join(tmp, dex), 'rb').read()
            ver = data[4:7]
            if ver not in API_FOR_VERSION:
                sys.exit(f'jar_smali: {dex} has unsupported dex version {ver!r}')
            sd = os.path.join(tmp, 's')
            subprocess.run(['baksmali', 'd', os.path.join(tmp, dex), '-o', sd], check=True,
                           stdout=subprocess.DEVNULL)
            host_file = os.path.join(sd, host + '.smali')
            for f in files:
                text = open(f, encoding='utf-8').read()
                first = real_lines(text)[0].strip()
                if first.startswith('.in-method '):
                    print(f'jar_smali: {dex} {host}: insertion from {os.path.basename(f)}')
                    insert_lines(host_file, os.path.basename(f), real_lines(text))
                elif first.startswith('.class '):
                    cls = first.split()[-1]
                    assert cls.startswith('L') and cls.endswith(';'), first
                    dst = os.path.join(sd, cls[1:-1] + '.smali')
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    print(f'jar_smali: {dex} {"replaced" if os.path.exists(dst) else "added"} class {cls}')
                    open(dst, 'w', encoding='utf-8').write(text)
                else:
                    print(f'jar_smali: {dex} {host}: methods from {os.path.basename(f)}')
                    replace_methods(host_file, os.path.basename(f), methods_of(text))
            nd = os.path.join(tmp, 'new.dex')
            subprocess.run(['smali', 'a', '--api', str(API_FOR_VERSION[ver]), sd, '-o', nd],
                           check=True, stdout=subprocess.DEVNULL)
            nb = open(nd, 'rb').read()
            if nb[4:7] != ver:
                sys.exit(f'jar_smali: {dex} came back as version {nb[4:7]!r}, was {ver!r}')
            out = os.path.join(tmp, 'out.jar')
            with zipfile.ZipFile(out, 'w', allowZip64=True) as zo:
                for it in zi.infolist():
                    zo.writestr(it, nb if it.filename == dex else zi.read(it), compress_type=it.compress_type)
        aligned = os.path.join(tmp, 'aligned.jar')
        subprocess.run(['zipalign', '-p', '-f', '4', out, aligned], check=True)
        with open(aligned, 'rb') as src, open(jar, 'r+b') as dst:   # keep owner, mode, label
            dst.truncate(0)
            shutil.copyfileobj(src, dst)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
