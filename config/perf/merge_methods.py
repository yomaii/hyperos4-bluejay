#!/usr/bin/env python3
"""Take the methods (except constructors) of a compiled partial class and give them the method headers of the
original class (keeps hiddenapi flags and modifiers), producing a method replacement file for jar_smali.py.

  merge_methods.py <generated.smali> <original.smali> <out.methods.smali> <note>
"""
import sys


def methods(text):
    out, cur = [], None
    for l in text.split('\n'):
        s = l.strip()
        if s.startswith('.method '):
            cur = [l]
        elif cur is not None:
            cur.append(l)
            if s == '.end method':
                out.append(cur)
                cur = None
    return out


gen, orig, out, note = sys.argv[1:5]
orig_heads = {}
for m in methods(open(orig, encoding='utf-8').read()):
    orig_heads.setdefault(m[0].split()[-1], []).append(m[0].strip())
res = ['# ' + note, '# Method headers from the original jar.', '']
n = 0
for m in methods(open(gen, encoding='utf-8').read()):
    sig = m[0].split()[-1]
    if sig.startswith('<init>') or sig.startswith('<clinit>'):
        continue
    heads = orig_heads.get(sig, [])
    if len(heads) != 1:
        sys.exit(f'merge_methods: {sig} found {len(heads)} times in {orig}, expected 1')
    res.append(heads[0])
    res.extend(m[1:])
    res.append('')
    n += 1
open(out, 'w', encoding='utf-8').write('\n'.join(res))
print(f'merge_methods: {n} methods -> {out}')
