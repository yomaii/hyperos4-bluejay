"""arsc_strings.py <in.apk> <out.apk> NAME=VALUE...

Set string/NAME to VALUE in every configuration of a prebuilt overlay APK and write a new,
unsigned APK (META-INF dropped, resources.arsc stored uncompressed; zipalign + apksigner afterwards).

Unlike arsc_replace.py (which rewrites one string in the pool, so every resource sharing it changes),
this changes individual resources: new values are appended to the global string pool and only the
named entries are pointed at them. The resource must already be a plain string.
Used for overlays whose several config strings share one pooled value
(e.g. FrameworksResCommon: three telephony service packages all "vendor.qti.iwlan").
"""
import struct, sys, zipfile


def read_pool(buf, off):
    typ, hsize, size, count, scount, flags, sstart, ststart = struct.unpack_from("<HHIIIIII", buf, off)
    assert typ == 0x0001, "not a string pool"
    utf8 = bool(flags & 0x100)
    strs = []
    for o in struct.unpack_from(f"<{count}I", buf, off + hsize):
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
    hdr = struct.pack("<HHIIIIII", 0x0001, hsize, sstart + len(data), len(strs), 0, flags, sstart, 0)
    return hdr + struct.pack(f"<{len(strs)}I", *offs) + bytes(data)


def entries(b, off, h, flags, cnt):
    idx = off + h
    for i in range(cnt):
        if flags & 0x01:    # sparse: (entry id, offset/4)
            eid, eo = struct.unpack_from("<HH", b, idx + 4 * i); yield eid, eo * 4
        elif flags & 0x02:  # 16-bit offsets (offset/4), 0xffff = none
            eo = struct.unpack_from("<H", b, idx + 2 * i)[0]
            if eo != 0xFFFF: yield i, eo * 4
        else:
            eo = struct.unpack_from("<I", b, idx + 4 * i)[0]
            if eo != 0xFFFFFFFF: yield i, eo


def set_strings(arsc, want):
    typ, hsize, total, npkg = struct.unpack_from("<HHII", arsc, 0)
    assert typ == 0x0002, "not a resource table"
    utf8, flags, scount, ststart, psize, strs = read_pool(arsc, hsize)
    if scount or ststart:
        sys.exit("styled strings in the pool are not supported")
    idx = {}
    for v in want.values():
        if v not in idx:
            idx[v] = strs.index(v) if v in strs else len(strs)
            if idx[v] == len(strs): strs.append(v)
    pool = build_pool(utf8, flags, strs)
    b = bytearray(struct.pack("<HHII", typ, hsize, 0, npkg) + arsc[12:hsize] + pool + arsc[hsize + psize:])
    struct.pack_into("<I", b, 4, len(b))
    hits = {k: [] for k in want}
    off = hsize
    while off < len(b):
        ct, ch, cs = struct.unpack_from("<HHI", b, off)
        if ct == 0x0200:  # package
            tso, _, kso = struct.unpack_from("<III", b, off + 268)
            types = read_pool(b, off + tso)[5]; keys = read_pool(b, off + kso)[5]
            t = off + ch
            while t < off + cs:
                tt, th, ts = struct.unpack_from("<HHI", b, t)
                if tt == 0x0201 and types[b[t + 8] - 1] == "string":
                    tflags, cnt, start = b[t + 9], *struct.unpack_from("<II", b, t + 12)
                    for _, eo in entries(b, t, th, tflags, cnt):
                        e = t + start + eo
                        esz, ef = struct.unpack_from("<HH", b, e)
                        if ef & 0x08:     # compact: key, flags|type<<8, data
                            key, dtype, dpos = esz, ef >> 8, e + 4
                        elif ef & 0x01:   # bag
                            continue
                        else:             # size, flags, key, Res_value{size,0,type,data}
                            key = struct.unpack_from("<I", b, e + 4)[0]; dtype, dpos = b[e + 11], e + 12
                        name = keys[key]
                        if name in want:
                            if dtype != 0x03:
                                sys.exit(f"string/{name} is not a plain string (type {dtype:#x})")
                            hits[name].append(strs[struct.unpack_from("<I", b, dpos)[0]])
                            struct.pack_into("<I", b, dpos, idx[want[name]])
                t += ts
        off += cs
    return bytes(b), hits


def main():
    a = sys.argv[1:]
    if len(a) < 3: sys.exit(__doc__)
    src, dst = a[0], a[1]
    want = dict(x.split("=", 1) for x in a[2:])
    with zipfile.ZipFile(src) as z:
        items = [(i, z.read(i.filename)) for i in z.infolist() if not i.filename.startswith("META-INF/")]
    with zipfile.ZipFile(dst, "w") as z:
        for i, d in items:
            if i.filename == "resources.arsc":
                d, hits = set_strings(d, want)
                for k, olds in hits.items():
                    if not olds: sys.exit(f"string/{k} not found")
                    print(f"  string/{k}: {', '.join(repr(o) for o in olds)} -> {want[k]!r}")
            zi = zipfile.ZipInfo(i.filename, date_time=i.date_time)
            zi.compress_type = zipfile.ZIP_STORED if i.filename == "resources.arsc" else i.compress_type
            zi.external_attr = i.external_attr
            z.writestr(zi, d)


main()
