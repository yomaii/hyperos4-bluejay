#!/usr/bin/env python3
"""Patch bytes inside a dex of an apk in place, without rewriting the zip, so the APK signing block stays.

  apk_dex_inplace.py <apk> <classesN.dex> <old hex> <new hex>

For platform-signed /system apps that cannot be re-signed. Boot-time scanning of /system apps takes the
certificate from the signing block and does not check content digests.

The dex entry must be stored, the old bytes must occur exactly once, old and new have the same length.
Updates the dex adler32/sha1 and the zip CRC32 (local header and central directory).
"""
import hashlib
import struct
import sys
import zlib


def main(apk, name, old_hex, new_hex):
    old, new = bytes.fromhex(old_hex), bytes.fromhex(new_hex)
    if len(old) != len(new):
        sys.exit('apk_dex_inplace: old and new must have the same length')
    raw = bytearray(open(apk, 'rb').read())
    eocd = raw.rfind(b'PK\x05\x06')
    if eocd < 0:
        sys.exit('apk_dex_inplace: no end of central directory')
    count, cd_size, cd_off = struct.unpack_from('<HII', raw, eocd + 10)
    p, hit = cd_off, None
    for _ in range(count):
        if raw[p:p + 4] != b'PK\x01\x02':
            sys.exit('apk_dex_inplace: bad central directory')
        method, = struct.unpack_from('<H', raw, p + 10)
        csize, usize, nlen, elen, clen = struct.unpack_from('<IIHHH', raw, p + 20)
        lho, = struct.unpack_from('<I', raw, p + 42)
        if raw[p + 46:p + 46 + nlen].decode('utf-8', 'replace') == name:
            hit = (p, method, csize, usize, lho)
        p += 46 + nlen + elen + clen
    if hit is None:
        sys.exit('apk_dex_inplace: not in apk: ' + name)
    cdp, method, csize, usize, lho = hit
    if method != 0 or csize != usize:
        sys.exit('apk_dex_inplace: %s is compressed' % name)
    if raw[lho:lho + 4] != b'PK\x03\x04':
        sys.exit('apk_dex_inplace: bad local header')
    flags, = struct.unpack_from('<H', raw, lho + 6)
    if flags & 0x8:
        sys.exit('apk_dex_inplace: data descriptors not supported')
    nlen, elen = struct.unpack_from('<HH', raw, lho + 26)
    start = lho + 30 + nlen + elen
    dex = bytearray(raw[start:start + usize])
    if dex[:4] != b'dex\n':
        sys.exit('apk_dex_inplace: %s is not a dex' % name)
    n = dex.count(old)
    if n != 1:
        sys.exit('apk_dex_inplace: old bytes found %d times in %s, expected 1' % (n, name))
    i = dex.find(old)
    dex[i:i + len(new)] = new
    dex[12:32] = hashlib.sha1(bytes(dex[32:])).digest()
    struct.pack_into('<I', dex, 8, zlib.adler32(bytes(dex[12:])) & 0xffffffff)
    crc = zlib.crc32(bytes(dex)) & 0xffffffff
    raw[start:start + usize] = dex
    struct.pack_into('<I', raw, lho + 14, crc)
    struct.pack_into('<I', raw, cdp + 16, crc)
    open(apk, 'wb').write(raw)
    print('apk_dex_inplace: %s @0x%x: %s -> %s' % (name, i, old_hex, new_hex))


if __name__ == '__main__':
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(*sys.argv[1:])
