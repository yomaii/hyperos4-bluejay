#!/usr/bin/env python3
"""Copy security.capability xattrs from one extracted tree onto another.

  copy_caps.py <tree_with_caps> <target_tree>

fsck.erofs --preserve sets xattrs first and chowns afterwards, and the kernel
drops file capabilities on chown. So unpack.sh extracts a second copy without
changing owners (capabilities survive there) and copies them back with this.
"""
import os
import stat
import sys

NAME = "security.capability"


def main(src, dst):
    n = 0
    for dirpath, _, files in os.walk(src):
        for f in files:
            s = os.path.join(dirpath, f)
            if not stat.S_ISREG(os.lstat(s).st_mode):
                continue
            try:
                cap = os.getxattr(s, NAME, follow_symlinks=False)
            except OSError:
                continue
            d = os.path.join(dst, os.path.relpath(s, src))
            os.setxattr(d, NAME, cap, follow_symlinks=False)
            n += 1
    print(f"  restored capabilities on {n} files")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2])
