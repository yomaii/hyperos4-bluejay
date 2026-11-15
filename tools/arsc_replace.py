"""arsc_replace.py <in.apk> <out.apk> <old string> <new string>

Replace one string in the global string pool of an APK's resources.arsc and write a new,
unsigned APK (META-INF dropped, resources.arsc stored uncompressed). Resource values point at
strings by index, so only the pool is rebuilt. Used to change config values in prebuilt
overlays without recompiling them (apktool can't rebuild HyperOS's overlays).
"""
import struct, sys, zipfile


def read_pool(buf, off):
    typ, hsize, size, count, scount, flags, sstart, ststart = struct.unpack_from("<HHIIIIII", buf, off)
    assert typ == 0x0001, "not a string pool"
    utf8 = bool(flags & 0x100)
    offs = struct.unpack_from(f"<{count}I", buf, off + hsize)
    strs = []
    for o in offs:
        p = off + sstart + o
        if utf8:
            n = buf[p]; p += 1
            if n & 0x80: p += 1
            n = buf[p]; p += 1
            if n & 0x80: n = ((n & 0x7F) << 8) | buf[p]; p += 1
            strs.append(buf[p:p + n].decode("utf-8"))
        else:
            n = struct.unpack_from("<H", buf, p)[0]; p += 2
            if n & 0x8000: n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", buf, p)[0]; p += 2
            strs.append(buf[p:p + 2 * n].decode("utf-16-le"))
    return utf8, flags, scount, ststart, size, strs


def enc_len8(n):
    return bytes([n]) if n < 0x80 else bytes([0x80 | (n >> 8), n & 0xFF])


def build_pool(utf8, flags, strs):
    data = bytearray(); offs = []
    for s in strs:
        offs.append(len(data))
        if utf8:
            b = s.encode("utf-8")
            data += enc_len8(len(s)) + enc_len8(len(b)) + b + b"\0"
        else:
            b = s.encode("utf-16-le"); n = len(b) // 2
            data += (struct.pack("<H", n) if n < 0x8000 else struct.pack("<HH", 0x8000 | (n >> 16), n & 0xFFFF)) + b + b"\0\0"
    while len(data) % 4:
        data += b"\0"
    hsize = 28
    sstart = hsize + 4 * len(strs)
    size = sstart + len(data)
    hdr = struct.pack("<HHIIIIII", 0x0001, hsize, size, len(strs), 0, flags, sstart, 0)
    return hdr + struct.pack(f"<{len(strs)}I", *offs) + bytes(data)


def main():
    src, dst, old, new = sys.argv[1:5]
    with zipfile.ZipFile(src) as z:
        items = [(i, z.read(i.filename)) for i in z.infolist() if not i.filename.startswith("META-INF/")]
    arsc = next(d for i, d in items if i.filename == "resources.arsc")
    typ, hsize, total, npkg = struct.unpack_from("<HHII", arsc, 0)
    assert typ == 0x0002, "not a resource table"
    utf8, flags, scount, ststart, psize, strs = read_pool(arsc, hsize)
    if scount or ststart:
        sys.exit("styled strings in the pool are not supported")
    hits = [k for k, s in enumerate(strs) if s == old]
    if len(hits) != 1:
        sys.exit(f"expected exactly one {old!r} in the string pool, found {len(hits)}")
    strs[hits[0]] = new
    pool = build_pool(utf8, flags, strs)
    rest = arsc[hsize + psize:]
    out = struct.pack("<HHII", typ, hsize, hsize + len(pool) + len(rest), npkg) + arsc[8 + 4:hsize] + pool + rest
    with zipfile.ZipFile(dst, "w") as z:
        for i, d in items:
            if i.filename == "resources.arsc":
                d = out
            zi = zipfile.ZipInfo(i.filename, date_time=i.date_time)
            zi.compress_type = zipfile.ZIP_STORED if i.filename == "resources.arsc" else i.compress_type
            zi.external_attr = i.external_attr
            z.writestr(zi, d)


main()
