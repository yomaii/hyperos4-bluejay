#!/usr/bin/env python3
"""Build a Module.symvers from stock .ko files.

  symvers_from_stock.py <out.symvers> <dir>...

CRCs come from each module's __versions section (what it imports, with the CRC the running kernel expects).
The exporting module comes from __ksymtab_strings; symbols no module exports are attributed to vmlinux.
"""
import os
import struct
import sys


def sections(path):
    d = open(path, 'rb').read()
    if d[:4] != b'\x7fELF' or d[4] != 2:
        return {}
    shoff, = struct.unpack_from('<Q', d, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', d, 0x3a)
    hdrs = [struct.unpack_from('<IIQQQQIIQQ', d, shoff + i * shentsize) for i in range(shnum)]
    stro = hdrs[shstrndx][4]
    out = {}
    for h in hdrs:
        name = d[stro + h[0]:d.index(b'\0', stro + h[0])].decode()
        out[name] = d[h[4]:h[4] + h[5]] if h[1] != 8 else b''   # SHT_NOBITS has no data
    return out


def main(out, dirs):
    crcs, exporter, conflicts = {}, {}, set()
    for top in dirs:
        for root, _, files in os.walk(top):
            for f in files:
                if not f.endswith('.ko'):
                    continue
                s = sections(os.path.join(root, f))
                v = s.get('__versions', b'')
                for off in range(0, len(v) - 63, 64):
                    crc, = struct.unpack_from('<Q', v, off)
                    name = v[off + 8:off + 64].split(b'\0')[0].decode()
                    if name in crcs and crcs[name] != crc:
                        conflicts.add(name)
                    crcs[name] = crc
                for name in s.get('__ksymtab_strings', b'').split(b'\0'):
                    if name:
                        exporter.setdefault(name.decode(), f[:-3])
    if conflicts:
        sys.exit(f'symvers_from_stock: conflicting CRCs for {sorted(conflicts)[:10]}')
    with open(out, 'w') as fo:
        for name in sorted(crcs):
            fo.write('0x%08x\t%s\t%s\tEXPORT_SYMBOL_GPL\t\n' % (crcs[name], name, exporter.get(name, 'vmlinux')))
    print(f'symvers_from_stock: {len(crcs)} symbols')


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2:])
