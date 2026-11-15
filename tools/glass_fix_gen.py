#!/usr/bin/env python3
# Fix for the hole in liquid glass surfaces on Mali: rewrite curve() in the corner SDF generator shader
# (SkSL text in libhwui.so at 0xc0e49) without its early return "if(x >= 0.85) return 1.0;", which is
# miscomputed on the Pixel 6a. Same result mathematically, same or shorter length.
#   glass_fix_gen.py libhwui.so out.so
import sys, re
OFF = 0xc0e49
data = bytearray(open(sys.argv[1], 'rb').read())
end = data.index(b'\0', OFF)
s = data[OFF:end].decode('utf-8')
m = re.search(r'float curve\(float x, float powRatio\)\s*\{.*?return circlePow;\s*\}', s, re.S)
if not m or 'if(x >= 0.85)' not in m.group(): sys.exit('curve() not found, different libhwui?')
s = s[:m.start()] + '''float curve(float x, float powRatio)
{
float c = smooth5_vertical(_clamp(x), 0.5);
float p = 1.0 - pow(max(1.0 - c, 0.0), powRatio);
return x >= 0.85 ? 1.0 : p;
}''' + s[m.end():]
s = re.sub(r'//[^\n]*', '', s)
s = re.sub(r'\n\s+', '\n', s)
new = s.encode('utf-8')
if len(new) > end - OFF: sys.exit('result is longer than the original')
data[OFF:end] = new + b' ' * (end - OFF - len(new))
open(sys.argv[2], 'wb').write(data)
print('ok', len(new), '/', end - OFF)
