"""Print a Linux vtable and a Windows vtable slot by slot, with the names known for each slot.

Usage: python -I vtcmp.py <BaldursGateII> <linux symbols.json> <Baldur.exe> <win symbols.json> <linuxAddrPoint> <winVtableRVA> [n=40]
  linuxAddrPoint = _ZTV address + 16 (what constructors store); slots read through R_X86_64_RELATIVE relocations.
  winVtableRVA   = RVA the Windows constructor stores into the vptr.
Itanium has two destructor slots (D1, D0) where MSVC has one (scalar deleting dtor), so Linux slot i usually faces
Windows slot i-1, but MSVC can reorder some virtuals: compare bodies, never trust the index alone.
No game data is stored by this tool.
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pedis import PE  # noqa: E402


def elf_relative(path):
    d = open(path, 'rb').read()
    shoff, = struct.unpack_from('<Q', d, 0x28)
    se, sn = struct.unpack_from('<HH', d, 0x3a)
    rel = {}
    for i in range(sn):
        s = struct.unpack_from('<IIQQQQIIQQ', d, shoff + i * se)
        if s[1] == 4:  # SHT_RELA
            for k in range(s[5] // 24):
                off, info, add = struct.unpack_from('<QQq', d, s[4] + k * 24)
                if info & 0xffffffff == 8:  # R_X86_64_RELATIVE
                    rel[off] = add
    return rel


def main():
    elf, lsyms, exe, wsyms, la, wa = sys.argv[1:7]
    n = int(sys.argv[7]) if len(sys.argv) > 7 else 40
    la, wa = int(la, 16), int(wa, 16)
    rel = elf_relative(elf)
    ln = {}
    for f in json.load(open(lsyms))['functions']:
        ln.setdefault(int(f['addr'], 16), f['demangled'])
    wn = {}
    for x in json.load(open(wsyms)):
        wn.setdefault(int(x['addr'], 16), f"{x['demangled']} [{x['confidence']}]")
    pe = PE(exe)
    for i in range(n):
        lt = rel.get(la + 8 * i)
        wt = struct.unpack('<Q', pe.read(wa + 8 * i, 8))[0] - pe.base
        ls = f'{lt:#x} {ln.get(lt, "")[:55]}' if lt else '-'
        print(f'{8 * i:#06x}  L {ls:<66} | W {wt:#x} {wn.get(wt, "")[:60]}')


if __name__ == '__main__':
    main()
