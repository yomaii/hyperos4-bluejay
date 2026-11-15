"""apk_patch.py <in.apk> <out.apk> [--file ZIP_PATH=LOCAL_FILE]... [--dimen NAME=<N>px]...

Patch a prebuilt overlay APK without recompiling it and write a new, unsigned APK
(META-INF dropped, resources.arsc stored uncompressed; zipalign + apksigner afterwards).

  --file   replace one file inside the APK (it must already exist)
  --dimen  set dimen/NAME to N px in every configuration that defines it. Values are stored
           inline in resources.arsc, so the table is changed in place; the resource must
           already be a dimension. Handles the sparse / 16-bit-offset / compact entry
           encodings that Android 15+ aapt2 writes.
"""
import struct, sys, zipfile


def read_pool(buf, off):
    _, hsize, _, count, _, flags, sstart, _ = struct.unpack_from("<HHIIIIII", buf, off)
    utf8 = bool(flags & 0x100)
    out = []
    for o in struct.unpack_from(f"<{count}I", buf, off + hsize):
        p = off + sstart + o
        if utf8:
            n = buf[p]; p += 1
            if n & 0x80: p += 1
            n = buf[p]; p += 1
            if n & 0x80: n = ((n & 0x7F) << 8) | buf[p]; p += 1
            out.append(buf[p:p + n].decode("utf-8", "replace"))
        else:
            n = struct.unpack_from("<H", buf, p)[0]; p += 2
            if n & 0x8000: n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", buf, p)[0]; p += 2
            out.append(buf[p:p + 2 * n].decode("utf-16-le", "replace"))
    return out


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


def set_dimens(arsc, want):
    """want: {name: px}. Returns patched bytes and {name: [old values]}."""
    b = bytearray(arsc)
    _, hsize, total, _ = struct.unpack_from("<HHII", b, 0)
    hits = {k: [] for k in want}
    off = hsize
    while off < total:
        ct, ch, cs = struct.unpack_from("<HHI", b, off)
        if ct == 0x0200:  # package
            tso, _, kso = struct.unpack_from("<III", b, off + 268)
            types = read_pool(b, off + tso); keys = read_pool(b, off + kso)
            t = off + ch
            while t < off + cs:
                tt, th, ts = struct.unpack_from("<HHI", b, t)
                if tt == 0x0201 and types[b[t + 8] - 1] == "dimen":
                    flags, cnt, start = b[t + 9], *struct.unpack_from("<II", b, t + 12)
                    for _, eo in entries(b, t, th, flags, cnt):
                        e = t + start + eo
                        esz, ef = struct.unpack_from("<HH", b, e)
                        if ef & 0x08:                     # compact: key, flags|type<<8, data
                            key, dtype, dpos = esz, ef >> 8, e + 4
                        elif ef & 0x01:                   # complex (bag) entry: not a plain dimen
                            continue
                        else:                             # size, flags, key, Res_value{size,0,type,data}
                            key = struct.unpack_from("<I", b, e + 4)[0]; dtype, dpos = b[e + 11], e + 12
                        name = keys[key]
                        if name in want:
                            if dtype != 0x05:
                                sys.exit(f"dimen/{name} is not a plain dimension (type {dtype:#x})")
                            old = struct.unpack_from("<I", b, dpos)[0]
                            hits[name].append(old)
                            struct.pack_into("<I", b, dpos, (want[name] << 8) & 0xFFFFFF00)  # radix 23p0, unit px
                t += ts
        off += cs
    return bytes(b), hits


def fmt_dim(d):
    mant = struct.unpack("<i", struct.pack("<I", d & 0xFFFFFF00))[0] >> 8
    v = mant * [1, 1 / 128, 1 / 32768, 1 / 8388608][(d >> 4) & 3]
    return f"{v:g}{['px', 'dp', 'sp', 'pt', 'in', 'mm'][d & 0xF]}"


def main():
    a = sys.argv[1:]
    if len(a) < 2: sys.exit(__doc__)
    src, dst, rest = a[0], a[1], a[2:]
    files, dimens = {}, {}
    for opt, val in zip(rest[::2], rest[1::2]):
        k, v = val.split("=", 1)
        if opt == "--file": files[k] = open(v, "rb").read()
        elif opt == "--dimen":
            assert v.endswith("px"), "only px values"; dimens[k] = int(v[:-2])
        else: sys.exit(f"unknown option {opt}")
    with zipfile.ZipFile(src) as z:
        items = [(i, z.read(i.filename)) for i in z.infolist() if not i.filename.startswith("META-INF/")]
    names = {i.filename for i, _ in items}
    missing = set(files) - names
    if missing: sys.exit(f"not in {src}: {sorted(missing)}")
    with zipfile.ZipFile(dst, "w") as z:
        for i, d in items:
            if i.filename == "resources.arsc" and dimens:
                d, hits = set_dimens(d, dimens)
                for k, olds in hits.items():
                    if not olds: sys.exit(f"dimen/{k} not found")
                    print(f"  dimen/{k}: {', '.join(fmt_dim(o) for o in olds)} -> {dimens[k]}px")
            d = files.get(i.filename, d)
            zi = zipfile.ZipInfo(i.filename, date_time=i.date_time)
            zi.compress_type = zipfile.ZIP_STORED if i.filename == "resources.arsc" else i.compress_type
            zi.external_attr = i.external_attr
            z.writestr(zi, d)


main()
