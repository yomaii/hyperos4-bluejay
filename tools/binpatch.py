#!/usr/bin/env python3
"""Replace bytes at an offset after checking the original bytes.

  binpatch.py <file> <hex offset> <old hex> <new hex>

Fails if the current bytes are neither old nor new.
"""
import sys


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    path, off, old, new = sys.argv[1], int(sys.argv[2], 16), bytes.fromhex(sys.argv[3]), bytes.fromhex(sys.argv[4])
    if len(old) != len(new):
        sys.exit("old and new differ in length")
    with open(path, "r+b") as f:
        f.seek(off)
        cur = f.read(len(old))
        if cur == new:
            print(f"{path} @0x{off:x}: already patched")
            return
        if cur != old:
            sys.exit(f"{path} @0x{off:x}: found {cur.hex()}, expected {old.hex()}")
        f.seek(off)
        f.write(new)
    print(f"{path} @0x{off:x}: {old.hex()} -> {new.hex()}")


if __name__ == "__main__":
    main()
