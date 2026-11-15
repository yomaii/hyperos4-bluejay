#!/usr/bin/env python3
"""Compare two metadata lists written by dump_meta.py.

  compare_meta.py <expected.tsv> <actual.tsv>

Exit code 0 when every path has the same type, owner, mode, SELinux label,
capabilities and link target.
"""
import sys


def load(path):
    rows = {}
    with open(path, encoding="utf-8") as fh:
        next(fh)
        for line in fh:
            f = line.rstrip("\n").split("\t")
            rows[f[0]] = f[1:]
    return rows


def main(a, b):
    exp, act = load(a), load(b)
    cols = ["type", "uid", "gid", "mode", "selinux", "caps", "link"]
    missing = sorted(set(exp) - set(act))
    extra = sorted(set(act) - set(exp))
    diff = [(p, [(c, x, y) for c, x, y in zip(cols, exp[p], act[p]) if x != y]) for p in sorted(set(exp) & set(act))]
    diff = [(p, d) for p, d in diff if d]
    for title, items in (("missing", missing), ("extra", extra)):
        if items:
            print(f"  {title}: {len(items)}  e.g. {', '.join(items[:5])}")
    for p, d in diff[:15]:
        print(f"  differs {p}: " + "; ".join(f"{c} {x!r} -> {y!r}" for c, x, y in d))
    ok = not (missing or extra or diff)
    print(f"  {'OK' if ok else 'MISMATCH'}: {len(exp)} entries compared, {len(diff)} differ")
    return 0 if ok else 1


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
