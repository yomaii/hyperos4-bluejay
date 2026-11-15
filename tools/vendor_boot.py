#!/usr/bin/env python3
"""Patch the vendor_boot taken from the phone.

  vendor_boot.py <vendor_boot.img> <output vendor_boot.img> [module.ko ...]

- erofs: the stock first-stage fstabs (fstab.gs101, fstab.gs101-fips in the vendor ramdisk) only list ext4 for
  system / system_ext / product. An erofs line is added before each ext4 one (fs_mgr tries entries for the
  same mount point in order).
- modules: a module that exists in lib/modules replaces it; a new one is added to lib/modules next to
  modules.load and appended to modules.load and modules.dep.

Other cpio entries, mkbootimg arguments and the vbmeta blob are kept (the hash no longer matches: flash with
vbmeta verification disabled). Needs unpack_bootimg, mkbootimg and lz4.
"""
import os
import re
import struct
import subprocess
import sys
import tempfile

MOUNTS = ("/system", "/system_ext", "/product")
CPIO_MAGICS = (b"070701", b"070702")
LZ4_OPTS = {b"\x02\x21\x4c\x18": ["-l", "-12", "--favor-decSpeed"],   # legacy frame
            b"\x04\x22\x4d\x18": ["-12", "--favor-decSpeed"]}
AVB_FOOTER = struct.Struct(">4sIIQQQ28s")
MODDIR = "lib/modules/"


def fstab_erofs(text):
    """Return text with an erofs line before each ext4 line for MOUNTS, and how many were added."""
    lines = text.splitlines()
    live = lambda l: not l.lstrip().startswith("#") and len(l.split()) >= 5
    has = {l.split()[1] for l in lines if live(l) and l.split()[2] == "erofs"}
    out, n = [], 0
    for l in lines:
        f = l.split()
        if live(l) and f[1] in MOUNTS and f[2] != "erofs" and f[1] not in has:
            tok = re.split(r"(\s+)", l)           # keep the alignment
            tok[4] = "erofs".ljust(len(tok[4]))
            tok[6] = "ro".ljust(len(tok[6]))      # erofs only needs ro
            out.append("".join(tok))
            has.add(f[1]); n += 1
        out.append(l)
    return "\n".join(out) + "\n", n


def pad4(n):
    return (4 - n % 4) % 4


class Entry:
    def __init__(self, hdr, name, body):
        self.hdr, self.magic, self.name, self.body = hdr, hdr[:6], name, body
        self.fields = [int(hdr[6 + 8 * i:14 + 8 * i], 16) for i in range(13)]
        self.orig = list(self.fields)

    def header(self):
        if self.fields == self.orig:
            return self.hdr
        fmt = b"%08x" if self.hdr[6:].lower() == self.hdr[6:] else b"%08X"   # keep the hex case
        return self.magic + b"".join(fmt % f for f in self.fields)

    @property
    def path(self):
        return self.name.rstrip(b"\0").decode("utf-8", "surrogateescape").lstrip("./")

    def set_body(self, body):
        self.body = body
        self.fields[6] = len(body)
        if self.magic == b"070702":
            self.fields[12] = sum(body) & 0xFFFFFFFF


def cpio_parse(data):
    """newc cpio (concatenated archives allowed) -> list of Entry and bytes (padding between archives)."""
    items, pos = [], 0
    while pos < len(data):
        if data[pos:pos + 6] not in CPIO_MAGICS:   # zero padding between or after archives
            nxt = min((i for i in (data.find(m, pos) for m in CPIO_MAGICS) if i != -1), default=len(data))
            if data[pos:nxt].strip(b"\0"):
                sys.exit(f"cpio: unexpected bytes at offset {pos}")
            items.append(data[pos:nxt]); pos = nxt
            continue
        e = Entry(data[pos:pos + 110], b"", b"")
        size, namesize = e.fields[6], e.fields[11]
        name_start = pos + 110
        body_start = name_start + namesize + pad4(110 + namesize)
        e.name, e.body = data[name_start:name_start + namesize], data[body_start:body_start + size]
        items.append(e)
        pos = body_start + size + pad4(size)
    return items


def cpio_dump(items):
    out = bytearray()
    for it in items:
        if isinstance(it, bytes):
            out += it
            continue
        out += it.header()
        out += it.name + b"\0" * pad4(110 + len(it.name))
        out += it.body + b"\0" * pad4(len(it.body))
    return bytes(out)


def is_file(e):
    return isinstance(e, Entry) and e.fields[1] & 0o170000 == 0o100000


def patch_fstabs(items):
    done = []
    for e in items:
        if is_file(e) and os.path.basename(e.path).startswith("fstab."):
            text, n = fstab_erofs(e.body.decode("utf-8"))
            if n:
                e.set_body(text.encode("utf-8"))
                done.append(f"{e.path} (+{n} erofs)")
    return done


def modinfo_depends(ko):
    for kv in open(ko, "rb").read().split(b"\0"):
        if kv.startswith(b"depends="):
            return [d for d in kv[8:].decode().split(",") if d]
    return []


def add_modules(frags, modules):
    """frags: {name: items}. Replace or add each module; returns {frag name: [messages]}."""
    done = {}
    find = lambda path: [(f, e) for f, items in frags.items() for e in items
                         if isinstance(e, Entry) and e.path == path]
    load = find(MODDIR + "modules.load")
    if len(load) != 1:
        sys.exit(f"vendor_boot: expected one {MODDIR}modules.load, found {len(load)}")
    lfrag, load = load[0]
    (_, dep), = find(MODDIR + "modules.dep")
    items = frags[lfrag]
    deps = {}
    for l in dep.body.decode().splitlines():
        k, _, v = l.partition(":")
        deps[os.path.basename(k)[:-3].replace("_", "-")] = (k, v.split())
    for ko in modules:
        base = os.path.basename(ko)
        body = open(ko, "rb").read()
        old = find(MODDIR + base)
        if old:
            for f, e in old:
                e.set_body(body)
                done.setdefault(f, []).append(f"{base} replaced")
            continue
        line = []
        for d in modinfo_depends(ko):
            k, v = deps.get(d.replace("_", "-"), (None, None))
            if k is None:
                sys.exit(f"vendor_boot: {base} depends on {d}, which is not in modules.dep")
            line += [x for x in [k] + v if x not in line]
        trailer = next(i for i in range(items.index(load), len(items))
                       if isinstance(items[i], Entry) and items[i].path == "TRAILER!!!")
        ino = max(e.fields[0] for e in items[:trailer] if isinstance(e, Entry)) + 1
        new = Entry(load.hdr, (MODDIR + base).encode() + b"\0", b"")
        new.fields[0], new.fields[11] = ino, len(new.name)
        new.set_body(body)
        items.insert(trailer, new)
        load.set_body(load.body + (b"" if load.body.endswith(b"\n") else b"\n") + base.encode() + b"\n")
        dep.set_body(dep.body + f"/{MODDIR}{base}:{''.join(' ' + x for x in line)}\n".encode())
        done.setdefault(lfrag, []).append(f"{base} added")
    return done


def unpack(img, out):
    r = subprocess.run(["unpack_bootimg", "--boot_img", img, "--out", out, "--format=mkbootimg", "-0"],
                       check=True, stdout=subprocess.PIPE)
    args = r.stdout.split(b"\0")
    return args[:-1] if args and not args[-1] else args   # keep empty arguments, drop the trailing one


def main(src, dst, modules):
    w = tempfile.mkdtemp(dir=os.path.dirname(os.path.abspath(dst)))   # not /tmp (tmpfs on WSL)
    u = os.path.join(w, "u")
    args = unpack(src, u)
    frags, opts, msgs = {}, {}, {}
    for f in sorted(os.listdir(u)):
        if not f.startswith("vendor_ramdisk"):
            continue
        p = os.path.join(u, f)
        opts[f] = LZ4_OPTS.get(open(p, "rb").read(4))
        if opts[f] is None:
            print(f"{f}: not lz4, skipped"); continue
        raw = subprocess.run(["lz4", "-dcq", p], check=True, stdout=subprocess.PIPE).stdout
        frags[f] = cpio_parse(raw)
        if cpio_dump(frags[f]) != raw:
            sys.exit(f"{f}: cpio does not round-trip")
        msgs[f] = patch_fstabs(frags[f])
    if not any(msgs.values()):
        sys.exit("no fstab patched")
    for f, m in add_modules(frags, modules).items():
        msgs[f] += m
    for f, m in msgs.items():
        if m:
            subprocess.run(["lz4", "-qf", *opts[f], "-", os.path.join(u, f)], input=cpio_dump(frags[f]), check=True)
            print(f"{f}: {', '.join(m)}")
    new_img = os.path.join(w, "vb.img")
    subprocess.run(["mkbootimg", *[a.decode("utf-8", "surrogateescape") for a in args], "--vendor_boot", new_img],
                   check=True)

    # Same partition size as the original; the original vbmeta blob goes right after the image (4 KiB aligned)
    # and the footer points at it.
    orig, img = open(src, "rb").read(), open(new_img, "rb").read()
    magic, major, minor, _, vb_off, vb_size, rsv = AVB_FOOTER.unpack(orig[-64:])
    if magic != b"AVBf":
        print("original has no AVB footer")
    else:
        off = -(-len(img) // 4096) * 4096
        if off + vb_size > len(orig) - 64:
            sys.exit(f"new image ({len(img)} bytes) does not fit in the {len(orig)} byte partition")
        img += b"\0" * (off - len(img)) + orig[vb_off:vb_off + vb_size]
        img += b"\0" * (len(orig) - 64 - len(img)) + AVB_FOOTER.pack(magic, major, minor, off, off, vb_size, rsv)
    open(dst, "wb").write(img)

    # check: same mkbootimg arguments
    norm = lambda a, d: [x.replace(d.encode(), b"X") for x in a]
    c = os.path.join(w, "check")
    if norm(unpack(dst, c), c) != norm(args, u):
        sys.exit("mkbootimg arguments differ from the original")
    print(f"ok: {dst}")
    subprocess.run(["rm", "-rf", w])


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
