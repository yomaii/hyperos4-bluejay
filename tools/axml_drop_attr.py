"""axml_drop_attr.py <in.apk> <out.apk> <element> <attr resource id, e.g. 0x0101000b>

Neutralise one android: attribute in a prebuilt APK's binary AndroidManifest.xml and write a new,
unsigned APK (META-INF dropped; zipalign + apksigner afterwards).

The framework reads manifest attributes by resource id (the XML resource map). The attribute's name
is pointed at a string that has no resource id (its own value string), so the parser no longer sees
it. Nothing is resized, so offsets stay valid. Used to drop android:sharedUserId="android.uid.system"
from Pixel's Iwlan: that uid needs Google's platform key, which this port can't sign with.
"""
import struct, sys, zipfile


def patch(axml, element, rid):
    b = bytearray(axml)
    typ, hsize, total = struct.unpack_from("<HHI", b, 0)
    assert typ == 0x0003, "not a binary XML"
    off = hsize
    strs_off = None; resmap = []
    hits = 0
    while off < total:
        ct, ch, cs = struct.unpack_from("<HHI", b, off)
        if ct == 0x0001:
            strs_off = off
            count = struct.unpack_from("<I", b, off + 8)[0]
        elif ct == 0x0180:
            resmap = list(struct.unpack_from(f"<{(cs - ch) // 4}I", b, off + ch))
        elif ct == 0x0102:  # start element
            name = struct.unpack_from("<I", b, off + 16 + 4)[0]
            astart, asize, acount = struct.unpack_from("<HHH", b, off + 16 + 8)
            if sname(b, strs_off, name) == element:
                for k in range(acount):
                    a = off + 16 + astart + k * asize
                    an, raw = struct.unpack_from("<II", b, a + 4)
                    if an < len(resmap) and resmap[an] == rid:
                        if raw == 0xFFFFFFFF or raw < len(resmap):
                            sys.exit("attribute has no usable value string to rename to")
                        print(f"  <{element}> {rid:#010x} = {sname(b, strs_off, raw)!r}: dropped")
                        struct.pack_into("<I", b, a + 4, raw)
                        hits += 1
        off += cs
    if hits != 1:
        sys.exit(f"expected one {rid:#010x} on <{element}>, found {hits}")
    return bytes(b)


def sname(b, pool, i):
    _, hsize, _, count, _, flags, sstart, _ = struct.unpack_from("<HHIIIIII", b, pool)
    p = pool + sstart + struct.unpack_from("<I", b, pool + hsize + 4 * i)[0]
    if flags & 0x100:
        n = b[p]; p += 1
        if n & 0x80: p += 1
        n = b[p]; p += 1
        if n & 0x80: n = ((n & 0x7F) << 8) | b[p]; p += 1
        return b[p:p + n].decode("utf-8")
    n = struct.unpack_from("<H", b, p)[0]; p += 2
    if n & 0x8000: n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", b, p)[0]; p += 2
    return b[p:p + 2 * n].decode("utf-16-le")


def main():
    if len(sys.argv) != 5: sys.exit(__doc__)
    src, dst, element, rid = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4], 16)
    with zipfile.ZipFile(src) as z:
        items = [(i, z.read(i.filename)) for i in z.infolist() if not i.filename.startswith("META-INF/")]
    with zipfile.ZipFile(dst, "w") as z:
        for i, d in items:
            if i.filename == "AndroidManifest.xml":
                d = patch(d, element, rid)
            zi = zipfile.ZipInfo(i.filename, date_time=i.date_time)
            zi.compress_type = i.compress_type
            zi.external_attr = i.external_attr
            z.writestr(zi, d)


main()
