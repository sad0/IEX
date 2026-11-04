"""Disassemble a range of a PE x64 image by RVA (capstone), for quick manual checks.

Usage:
  python -I pedis.py <exe> <rva> [count=40]        disassemble <count> instructions from <rva>
  python -I pedis.py <exe> --back <rva> [count=30]  show ~<count> instructions ending at <rva>
  python -I pedis.py <exe> --q <rva> [n=8]          dump n qwords at <rva> (vtables, tables)
RVA-relative targets are printed as RVAs. No game data is stored by this tool.
"""
import struct
import sys

import capstone


class PE:
    def __init__(self, path):
        self.data = open(path, 'rb').read()
        d = self.data
        pe = struct.unpack_from('<I', d, 0x3c)[0]
        nsec = struct.unpack_from('<H', d, pe + 6)[0]
        optsz = struct.unpack_from('<H', d, pe + 20)[0]
        opt = pe + 24
        self.base = struct.unpack_from('<Q', d, opt + 24)[0]
        self.secs = []
        for i in range(nsec):
            o = opt + optsz + 40 * i
            name = d[o:o + 8].rstrip(b'\0').decode()
            vsz, va, rsz, raw = struct.unpack_from('<IIII', d, o + 8)
            self.secs.append((name, va, max(vsz, rsz), raw, rsz))

    def read(self, rva, n):
        for name, va, sz, raw, rsz in self.secs:
            if va <= rva < va + sz:
                off = rva - va
                b = self.data[raw + off: raw + min(off + n, rsz)]
                return b + b'\0' * (n - len(b))
        raise ValueError('rva %x not mapped' % rva)


def main():
    a = sys.argv[1:]
    pe = PE(a[0])
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    if a[1] == '--q':
        rva = int(a[2], 16)
        n = int(a[3]) if len(a) > 3 else 8
        for i in range(n):
            q = struct.unpack_from('<Q', pe.read(rva + 8 * i, 8))[0]
            print('%x: %x%s' % (rva + 8 * i, q, ' (rva %x)' % (q - pe.base) if pe.base <= q < pe.base + 0x10000000 else ''))
        return
    back = a[1] == '--back'
    if back:
        a = a[1:]
    rva = int(a[1], 16)
    cnt = int(a[2]) if len(a) > 2 else (30 if back else 40)
    start = rva
    if back:  # find a start address whose linear decode lands exactly on rva
        for s in range(rva - cnt * 6, rva - cnt * 2):
            code = pe.read(s, rva - s + 16)
            if any(i.address - pe.base == rva for i in md.disasm(code, pe.base + s)):
                start = s
                break
    code = pe.read(start, cnt * 16 if not back else rva - start + 16)
    out = []
    for ins in md.disasm(code, pe.base + start):
        r = ins.address - pe.base
        out.append('%x: %-8s %s' % (r, ins.mnemonic, ins.op_str.replace(hex(pe.base)[:-3], '~')))
        if back and r >= rva:
            break
        if not back and len(out) >= cnt:
            break
    print('\n'.join(out[-cnt:] if back else out))


if __name__ == '__main__':
    main()
