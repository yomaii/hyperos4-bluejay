#!/usr/bin/env python3
"""Compile the SELinux policy the way init does at boot, to catch broken policy before flashing.

  sepolicy_check.py <system root> <system_ext> <product> <vendor> [odm]

The file list and order follow init's CompilePolicy() (system/core/init/selinux.cpp).
Exit code 0 when secilc compiles it.
"""
import os
import re
import subprocess
import sys


def main(sysroot, system_ext, product, vendor, odm=None):
    odm = odm or os.path.join(vendor, "odm")
    with open(os.path.join(vendor, "etc/selinux/plat_sepolicy_vers.txt")) as fh:
        ver = fh.read().strip()
    # init reads vendor/etc/selinux/genfs_labels_version.txt first, then build.prop
    genfs = None
    gv = os.path.join(vendor, "etc/selinux/genfs_labels_version.txt")
    bp = os.path.join(vendor, "build.prop")
    if os.path.exists(gv):
        genfs = open(gv).read().strip() or None
    elif os.path.exists(bp):
        m = re.search(r"^ro\.board\.genfs_labels_version=(\S+)", open(bp).read(), re.M)
        genfs = m.group(1) if m else None
    cand = [
        (sysroot, "etc/selinux/plat_sepolicy.cil", True),
        (sysroot, f"etc/selinux/mapping/{ver}.cil", True),
        (sysroot, f"etc/selinux/mapping/{ver}.compat.cil", False),
        (system_ext, "etc/selinux/system_ext_sepolicy.cil", False),
        (system_ext, f"etc/selinux/mapping/{ver}.cil", False),
        (system_ext, f"etc/selinux/mapping/{ver}.compat.cil", False),
        (product, "etc/selinux/product_sepolicy.cil", False),
        (product, f"etc/selinux/mapping/{ver}.cil", False),
        (vendor, "etc/selinux/plat_pub_versioned.cil", True),
        (vendor, "etc/selinux/vendor_sepolicy.cil", True),
        (odm, "etc/selinux/odm_sepolicy.cil", False),
    ]
    if genfs:
        cand.append((sysroot, f"etc/selinux/plat_sepolicy_genfs_{genfs}.cil", False))
    files = []
    for base, rel, required in cand:
        f = os.path.join(base, rel)
        if os.path.exists(f):
            files.append(f)
        elif required:
            print(f"  missing {f}")
            return 1
    cmd = ["secilc", "-m", "-M", "true", "-G", "-N", "-c", "30", *files, "-o", os.devnull, "-f", os.devnull]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode == 0:
        print(f"  OK: policy compiles ({len(files)} files, vendor version {ver})")
        return 0
    print("  FAILED:\n" + (p.stdout + p.stderr).strip()[-3000:])
    return 1


if __name__ == "__main__":
    if len(sys.argv) not in (5, 6):
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(*sys.argv[1:]))
