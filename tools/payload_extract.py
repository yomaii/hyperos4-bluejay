#!/usr/bin/env python3
"""Extract partition images from the payload.bin of a full A/B OTA.

    payload_extract.py list <ota.zip | payload.bin>
    payload_extract.py extract <ota.zip | payload.bin> <out_dir> [partition ...]

Reads payload.bin straight from the zip (it is stored). Full OTAs only. Sizes and sha256 are checked
against new_partition_info.
"""
import bz2
import concurrent.futures as cf
import hashlib
import lzma
import os
import struct
import subprocess
import sys
import zipfile

# InstallOperation.Type
OP_NAMES = {0: "REPLACE", 1: "REPLACE_BZ", 2: "MOVE", 3: "BSDIFF", 4: "SOURCE_COPY",
            5: "SOURCE_BSDIFF", 6: "ZERO", 7: "DISCARD", 8: "REPLACE_XZ", 9: "PUFFDIFF",
            10: "BROTLI_BSDIFF", 11: "ZUCCHINI", 12: "LZ4DIFF_BSDIFF", 13: "LZ4DIFF_PUFFDIFF",
            14: "REPLACE_ZSTD"}
ZSTD_MAGIC = b"\x28\xb5\x2f\xfd"


# ---- minimal protobuf reader ----
def _varint(b, i):
    r = s = 0
    while True:
        c = b[i]
        i += 1
        r |= (c & 0x7F) << s
        s += 7
        if c < 0x80:
            return r, i


def fields(b):
    i, n = 0, len(b)
    while i < n:
        k, i = _varint(b, i)
        fn, wt = k >> 3, k & 7
        if wt == 0:
            v, i = _varint(b, i)
        elif wt == 2:
            l, i = _varint(b, i)
            v = b[i:i + l]
            i += l
        elif wt == 1:
            v = b[i:i + 8]
            i += 8
        elif wt == 5:
            v = b[i:i + 4]
            i += 4
        else:
            raise ValueError(f"protobuf wire type {wt}")
        yield fn, v


def extents(b):
    start = num = 0
    for fn, v in fields(b):
        if fn == 1:
            start = v
        elif fn == 2:
            num = v
    return start, num


def parse_op(b):
    op = {"type": 0, "off": 0, "len": 0, "dst": []}
    for fn, v in fields(b):
        if fn == 1:
            op["type"] = v
        elif fn == 2:
            op["off"] = v
        elif fn == 3:
            op["len"] = v
        elif fn == 6:
            op["dst"].append(extents(v))
    return op


def parse_partition(b):
    p = {"name": None, "size": None, "hash": None, "ops": []}
    for fn, v in fields(b):
        if fn == 1:
            p["name"] = v.decode()
        elif fn == 7:  # new_partition_info
            for f2, v2 in fields(v):
                if f2 == 1:
                    p["size"] = v2
                elif f2 == 2:
                    p["hash"] = v2
        elif fn == 8:
            p["ops"].append(parse_op(v))
    return p


# ---- open payload ----
def payload_location(path):
    """Return (path, offset of payload.bin in the file)."""
    if not zipfile.is_zipfile(path):
        return path, 0
    with zipfile.ZipFile(path) as z:
        info = z.getinfo("payload.bin")
        if info.compress_type != zipfile.ZIP_STORED:
            sys.exit("error: payload.bin is compressed in the zip, unzip it first")
    with open(path, "rb") as f:
        f.seek(info.header_offset)
        h = f.read(30)
        if h[:4] != b"PK\x03\x04":
            sys.exit("error: bad zip local header")
        name_len, extra_len = struct.unpack("<HH", h[26:30])
        return path, info.header_offset + 30 + name_len + extra_len


def read_manifest(path):
    fpath, base = payload_location(path)
    with open(fpath, "rb") as f:
        f.seek(base)
        hdr = f.read(24)
        if hdr[:4] != b"CrAU":
            sys.exit("error: not a payload.bin (no CrAU magic)")
        ver, msize = struct.unpack(">QQ", hdr[4:20])
        if ver < 2:
            sys.exit(f"error: unsupported payload version {ver}")
        sigsize = struct.unpack(">I", hdr[20:24])[0]
        manifest = f.read(msize)
    block_size = 4096
    parts = []
    for fn, v in fields(manifest):
        if fn == 3:
            block_size = v
        elif fn == 13:
            parts.append(parse_partition(v))
    data_base = base + 24 + msize + sigsize
    return fpath, data_base, block_size, parts


# ---- extract ----
def decompress(t, data):
    if t == 0:
        return data
    if t == 1:
        return bz2.decompress(data)
    if t == 8:
        return lzma.decompress(data)
    if t == 14 or data[:4] == ZSTD_MAGIC:
        return subprocess.run(["zstd", "-dcq"], input=data, stdout=subprocess.PIPE,
                              check=True).stdout
    raise ValueError(f"unsupported operation {OP_NAMES.get(t, t)} (incremental OTA?)")


def extract_partition(src, data_base, bs, p, out_path, workers):
    total = p["size"]
    with open(out_path, "wb") as o:
        o.truncate(total)
    in_fd = os.open(src, os.O_RDONLY)
    out_fd = os.open(out_path, os.O_WRONLY)
    try:
        def run(op):
            t = op["type"]
            if t in (6, 7):  # ZERO / DISCARD: the file is already zero-filled
                return
            data = os.pread(in_fd, op["len"], data_base + op["off"])
            if len(data) != op["len"]:
                raise IOError("short read (truncated file?)")
            buf = decompress(t, data)
            pos = 0
            for start, num in op["dst"]:
                n = num * bs
                os.pwrite(out_fd, buf[pos:pos + n], start * bs)
                pos += n
            if pos != len(buf):
                raise ValueError(f"decompressed size {len(buf)} != {pos}")

        bad = [OP_NAMES.get(op["type"], op["type"]) for op in p["ops"]
               if op["type"] not in (0, 1, 6, 7, 8, 14)]
        if bad:
            raise ValueError(f"{p['name']}: unsupported operations {sorted(set(map(str, bad)))} (incremental OTA?)")
        # lzma / bz2 release the GIL, so threads run in parallel
        with cf.ThreadPoolExecutor(workers) as ex:
            for fut in cf.as_completed([ex.submit(run, op) for op in p["ops"]]):
                fut.result()
    finally:
        os.close(in_fd)
        os.close(out_fd)

    h = hashlib.sha256()
    with open(out_path, "rb") as f:
        for chunk in iter(lambda: f.read(16 << 20), b""):
            h.update(chunk)
    if p["hash"] and h.digest() != p["hash"]:
        raise ValueError(f"{p['name']} sha256 mismatch: {h.hexdigest()} != {p['hash'].hex()}")
    return h.hexdigest()


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("list", "extract"):
        sys.exit(__doc__)
    src, data_base, bs, parts = read_manifest(sys.argv[2])
    if sys.argv[1] == "list":
        for p in parts:
            kinds = sorted({OP_NAMES.get(o["type"], str(o["type"])) for o in p["ops"]})
            print(f"{p['name']}\t{p['size']}\t{','.join(kinds)}")
        return
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    out_dir, want = sys.argv[3], sys.argv[4:]
    os.makedirs(out_dir, exist_ok=True)
    by_name = {p["name"]: p for p in parts}
    missing = [w for w in want if w not in by_name]
    if missing:
        print(f"note: not in payload, skipped: {' '.join(missing)}", file=sys.stderr)
    todo = [by_name[w] for w in want if w in by_name] if want else parts
    workers = os.cpu_count() or 4
    for p in todo:
        out = os.path.join(out_dir, p["name"] + ".img")
        digest = extract_partition(src, data_base, bs, p, out, workers)
        print(f"    payload -> {p['name']}.img  {p['size'] / 1048576:.1f} MiB  sha256 {digest[:16]}… ok")


if __name__ == "__main__":
    main()
