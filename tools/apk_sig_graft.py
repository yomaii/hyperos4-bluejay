#!/usr/bin/env python3
"""Put the APK signing block (v2/v3) of the original apk onto a modified apk, without re-signing.

  apk_sig_graft.py <original apk> <modified apk, zipaligned, unsigned> <output apk>

Like apk_dex_inplace.py, for platform-signed /system apps whose dex had to be reassembled.
Only works for apps on system partitions; pm install checks the digests.
"""
import struct
import sys

MAGIC = b'APK Sig Block 42'


def eocd(raw, name):
    i = raw.rfind(b'PK\x05\x06')
    if i < 0:
        sys.exit('apk_sig_graft: %s: no end of central directory' % name)
    cd_size, cd_off = struct.unpack_from('<II', raw, i + 12)
    if cd_off == 0xffffffff:
        sys.exit('apk_sig_graft: %s: zip64 not supported' % name)
    return i, cd_off


def main(orig, patched, out):
    o = open(orig, 'rb').read()
    _, ocd = eocd(o, orig)
    if o[ocd - 16:ocd] != MAGIC:
        sys.exit('apk_sig_graft: original apk has no signing block')
    size, = struct.unpack_from('<Q', o, ocd - 24)
    start = ocd - size - 8
    if start < 0 or struct.unpack_from('<Q', o, start)[0] != size:
        sys.exit('apk_sig_graft: bad signing block in original apk')
    block = o[start:ocd]

    p = bytearray(open(patched, 'rb').read())
    pe, pcd = eocd(p, patched)
    if p[pcd - 16:pcd] == MAGIC:
        sys.exit('apk_sig_graft: modified apk already has a signing block')
    pad = (-pcd) % 4096  # 4096 alignment, as apksigner does
    ins = b'\0' * pad + block
    res = p[:pcd] + ins + p[pcd:]
    struct.pack_into('<I', res, pe + len(ins) + 16, pcd + len(ins))
    open(out, 'wb').write(res)
    print('apk_sig_graft: %d byte block (central directory 0x%x -> 0x%x)' % (len(block), pcd, pcd + len(ins)))


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
