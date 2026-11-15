#!/usr/bin/env python3
"""Edit a build.prop in place.

  props.py drop  <build.prop> <keys file>   comment out the listed props ("# port dropped: <line>")
  props.py merge <build.prop> <prop file> <title>
                                            replace the same keys and append the lines under "# ---- <title> ----"
"""
import sys


def key(line):
    s = line.strip()
    if not s or s.startswith("#") or "=" not in s or s.startswith("import "):
        return None
    return s.split("=", 1)[0].strip()


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return [l.rstrip("\n") for l in fh]


def drop(target, keys_file):
    keys = {l.split("#", 1)[0].strip() for l in read(keys_file)} - {""}
    lines = read(target)
    n = 0
    for i, l in enumerate(lines):
        if key(l) in keys:
            lines[i] = "# port dropped: " + l
            n += 1
    if n:
        with open(target, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines) + "\n")
    print(f"  {target}: {n} props dropped")


def merge(target, source, title):
    src = [l for l in read(source) if key(l)]
    keys = {key(l) for l in src}
    old = read(target)
    kept = [l for l in old if key(l) not in keys]
    with open(target, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(kept).rstrip("\n") + f"\n\n# ---- {title} ----\n" + "\n".join(src) + "\n")
    print(f"  {title}: {len(src)} props added ({len(old) - len(kept)} existing lines replaced)")


if __name__ == "__main__":
    cmds = {"drop": (drop, 2), "merge": (merge, 3)}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds or len(sys.argv) != cmds[sys.argv[1]][1] + 2:
        sys.exit(__doc__)
    cmds[sys.argv[1]][0](*sys.argv[2:])
