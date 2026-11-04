"""Compare the field offsets used by two decompiled versions of the same function (Ghidra C output).

Usage: python -I offdiff.py <win.c> <winVar> <linux.c> <linuxVar> [lo:delta ...]
  Collects every "<var> + N", "(longlong)<var> + N" and "<var>[N]" (scaled by the pointer type
  declared in the signature, e.g. undefined8 * -> 8) and prints offsets found on one side only.
  Optional lo:delta (hex) pairs model a Windows shift: a Linux offset >= lo is compared at +delta
  (last matching pair wins). A clean result ("only W/L" empty or codegen noise) means the
  layout model holds for that function.
"""
import re
import sys

SZ = {'undefined8': 8, 'longlong': 8, 'ulonglong': 8, 'long': 8, 'undefined4': 4, 'int': 4, 'uint': 4,
      'undefined2': 2, 'short': 2, 'ushort': 2, 'undefined1': 1, 'char': 1, 'byte': 1, 'undefined': 1}


def elt(text, var):
    m = re.search(r'(\w+)\s*(\*?)\s*' + var + r'\b[,)]', text)
    return SZ.get(m.group(1), 1) if m and m.group(2) else 1


def offsets(path, var):
    t = open(path, encoding='utf-8', errors='replace').read()
    e = elt(t, var)
    s = set()
    for m in re.finditer(r'(\((?:long)?long\))?(?<![\w])' + var + r' \+ (0x[0-9a-f]+|\d+)', t):
        s.add(int(m.group(2), 0) * (1 if m.group(1) else e))
    for m in re.finditer(r'(?<![\w])' + var + r'\[(0x[0-9a-f]+|\d+)\]', t):
        s.add(int(m.group(1), 0) * e)
    return s


def main():
    a = sys.argv[1:]
    w = offsets(a[0], a[1])
    shifts = [tuple(int(v, 16) for v in x.split(':')) for x in a[4:]]
    lin = set()
    for x in offsets(a[2], a[3]):
        d = 0
        for lo, dd in shifts:
            if x >= lo:
                d = dd
        lin.add(x + d)
    print('common %d  W %d  L %d' % (len(w & lin), len(w), len(lin)))
    print('only W:', ' '.join(hex(x) for x in sorted(w - lin)))
    print('only L:', ' '.join(hex(x) for x in sorted(lin - w)))


if __name__ == '__main__':
    main()
