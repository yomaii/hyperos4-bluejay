#!/usr/bin/env python3
"""Record ownership, mode, SELinux label and capabilities of an extracted tree.

  dump_meta.py <extracted_dir> <out.tsv>

Columns: path type uid gid mode selinux capabilities link_target
Paths are relative to the partition root and start with "/".
The file is what we need later to rebuild the image with the same metadata.
"""
import os
import stat
import sys


def xattr(path, name):
    try:
        return os.getxattr(path, name, follow_symlinks=False)
    except OSError:
        return None


def ftype(mode):
    if stat.S_ISDIR(mode):
        return "d"
    if stat.S_ISLNK(mode):
        return "l"
    if stat.S_ISREG(mode):
        return "f"
    return "o"


def main(root, out_path):
    root = os.path.abspath(root)
    rows = labeled = with_caps = 0
    with open(out_path, "w", encoding="utf-8", newline="\n") as out:
        out.write("path\ttype\tuid\tgid\tmode\tselinux\tcapabilities\tlink\n")
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames.sort()
            for name in [None] + sorted(filenames) + [d for d in dirnames if os.path.islink(os.path.join(dirpath, d))]:
                full = dirpath if name is None else os.path.join(dirpath, name)
                st = os.lstat(full)
                rel = "/" + os.path.relpath(full, root).replace(os.sep, "/")
                if rel == "/.":
                    rel = "/"
                label = xattr(full, "security.selinux")
                caps = xattr(full, "security.capability")
                link = os.readlink(full) if stat.S_ISLNK(st.st_mode) else ""
                label_s = label.rstrip(b"\0").decode("utf-8", "replace") if label else ""
                out.write(f"{rel}\t{ftype(st.st_mode)}\t{st.st_uid}\t{st.st_gid}\t"
                          f"{stat.S_IMODE(st.st_mode):04o}\t{label_s}\t"
                          f"{caps.hex() if caps else ''}\t{link}\n")
                rows += 1
                labeled += bool(label)
                with_caps += bool(caps)
    print(f"  {rows} entries, {labeled} with SELinux label, {with_caps} with capabilities")
    if rows and not labeled:
        print("  warning: no SELinux labels found (extracted without xattrs?)", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2])
