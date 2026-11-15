#!/usr/bin/env python3
"""Set the refresh-rate entries of a HyperOS device_features XML.

  features_fps.py <in.xml> <out.xml> <fps> [<fps> ...]

fpsList becomes the given rates (highest first), defaultFps and smart_fps_value the
highest one. support_smart_fps stays true: MiSettings picks its page by it, and the
old page (support_smart_fps=false) draws its first option under the action bar on
HyperOS 4, so 90 Hz can't be tapped. Only those entries change; the rest of the file
is kept byte for byte.
"""
import re
import sys


def main(src, dst, rates):
    rates = sorted({int(r) for r in rates}, reverse=True)
    top = rates[0]
    s = open(src, encoding='utf-8').read()

    def sub(pattern, repl, what):
        nonlocal s
        s, n = re.subn(pattern, repl, s, count=1, flags=re.S)
        if n != 1:
            sys.exit(f'features_fps: {what} not found in {src}')

    sub(r'(<integer-array name="fpsList">)(\s*)(.*?)(\s*</integer-array>)',
        lambda m: m.group(1) + ''.join(m.group(2) + f'<item>{r}</item>' for r in rates) + m.group(4),
        'fpsList')
    sub(r'(<bool name="support_smart_fps">)\w+(</bool>)', r'\g<1>true\g<2>', 'support_smart_fps')
    sub(r'(<integer name="smart_fps_value">)\d+(</integer>)', rf'\g<1>{top}\g<2>', 'smart_fps_value')
    sub(r'(<integer name="defaultFps">)\d+(</integer>)', rf'\g<1>{top}\g<2>', 'defaultFps')
    open(dst, 'w', encoding='utf-8', newline='').write(s)
    print(f'  fpsList={rates} defaultFps={top} smart_fps_value={top} support_smart_fps=true')


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
