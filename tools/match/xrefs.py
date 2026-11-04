"""Find code references to an address in the Linux ELF or the Windows PE (capstone, linear per function).

Usage:
  python -I xrefs.py elf <BaldursGateII> <linux symbols.json> <addr> [addr...] [--dis A [n]]
  python -I xrefs.py pe  <Baldur.exe> <win_functions.jsonl> <rva> [rva...]   [--dis A [n]]
For each target prints every instruction of a known function that calls/jumps to it directly
("call"/"jmp" rel32, the printed address is the E8/E9 opcode) or references it RIP-relatively
(lea/mov/cmp... data refs): "<target> <site> in <funcAddr> <funcName>: <insn>".
ELF addresses are symtab VAs (Ghidra Linux project = VA + 0x100000), PE addresses are RVAs.
Also a raw byte scan of executable sections for E8/E9 rel32 hits outside known function bodies
(flagged "raw"), so calls from unlisted statics are not missed.
Targets: hex addresses, or s:<text> = every NUL-delimited occurrence of that string literal.
--dis A [n]: disassemble n instructions at A (ELF VA or PE RVA) instead.
No game data is stored by this tool.
"""
import bisect
import json
import re
import struct
import sys

import capstone
from capstone import x86

sys.path.insert(0, __import__('os').path.dirname(__file__))
from pedis import PE  # noqa: E402


class ELF:
    def __init__(self, path):
        d = self.data = open(path, 'rb').read()
        shoff, = struct.unpack_from('<Q', d, 0x28)
        shentsize, shnum = struct.unpack_from('<HH', d, 0x3a)
        self.secs = []
        for i in range(shnum):
            o = shoff + i * shentsize
            _, typ, flags, addr, off, size = struct.unpack_from('<IIQQQQ', d, o)
            if addr and typ != 8:  # skip NOBITS
                self.secs.append((addr, size, off, bool(flags & 4)))
        self.base = 0

    def read(self, va, n):
        for addr, size, off, _ in self.secs:
            if addr <= va < addr + size:
                k = min(n, addr + size - va)
                b = self.data[off + va - addr: off + va - addr + k]
                return b + b'\0' * (n - len(b))
        raise ValueError('va %x not mapped' % va)

    def exec_ranges(self):
        return [(a, a + s) for a, s, _, x in self.secs if x]


def pe_exec_ranges(pe):
    out = []
    d = pe.data
    peo = struct.unpack_from('<I', d, 0x3c)[0]
    nsec = struct.unpack_from('<H', d, peo + 6)[0]
    optsz = struct.unpack_from('<H', d, peo + 20)[0]
    for i in range(nsec):
        o = peo + 24 + optsz + 40 * i
        vsz, va = struct.unpack_from('<II', d, o + 8)
        ch = struct.unpack_from('<I', d, o + 36)[0]
        if ch & 0x20000000:
            out.append((va, va + vsz))
    return out


def load(kind, binp, fl):
    if kind == 'elf':
        img = ELF(binp)
        s = json.load(open(fl, encoding='utf-8'))
        funcs, seen = [], set()
        for f in s['functions']:
            a, n = int(f['addr'], 16), f['size']
            if n and a not in seen:
                seen.add(a)
                funcs.append((a, f['name'], [(a, a + n)]))
        return img, funcs, img.exec_ranges()
    img = PE(binp)
    funcs = []
    for line in open(fl):
        f = json.loads(line)
        if f.get('k') != 'fn' or f.get('thunk'):
            continue
        funcs.append((int(f['rva'], 16), f['name'],
                      [(int(a, 16), int(b, 16) + 1) for a, b in f['ranges']]))
    return img, funcs, pe_exec_ranges(img)


def main():
    a = sys.argv[1:]
    kind, binp, fl = a[0], a[1], a[2]
    img, funcs, xr = load(kind, binp, fl)
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True
    if '--dis' in a:
        i = a.index('--dis')
        s = int(a[i + 1], 16)
        n = int(a[i + 2]) if len(a) > i + 2 else 40
        for k, ins in enumerate(md.disasm(img.read(s, n * 15), img.base + s)):
            if k >= n:
                break
            print('%x: %-8s %s' % (ins.address - img.base, ins.mnemonic, ins.op_str))
        return
    targets = set()
    for x in a[3:]:
        if x.startswith('s:'):  # string literal -> every NUL-delimited occurrence in the image
            want = x[2:].encode() + b'\0'
            secs = ([(va, raw, rsz) for _, va, _, raw, rsz in img.secs] if kind == 'pe'
                    else [(va, off, size) for va, size, off, _ in img.secs])
            for va, off, size in secs:
                blob = img.data[off:off + size]
                for m in re.finditer(re.escape(want), blob):
                    if m.start() == 0 or blob[m.start() - 1] == 0:
                        t = va + m.start()
                        print('# string %r at %#x' % (x[2:], t))
                        targets.add(t)
        elif not x.startswith('--'):
            targets.add(int(x, 16))
    covered = []
    for fa, name, ranges in funcs:
        for s, e in ranges:
            covered.append((s, e))
            for ins in md.disasm(img.read(s, e - s), img.base + s):
                r = ins.address - img.base
                hit = None
                for op in ins.operands:
                    if op.type == x86.X86_OP_MEM and op.mem.base == x86.X86_REG_RIP:
                        t = ins.address + ins.size + op.mem.disp - img.base
                        if t in targets:
                            hit = t
                    elif op.type == x86.X86_OP_IMM and ins.mnemonic in ('call', 'jmp') and op.imm - img.base in targets:
                        hit = op.imm - img.base
                if hit is not None:
                    print('%#x %#x in %#x %s: %s %s' % (hit, r, fa, name, ins.mnemonic, ins.op_str))
    covered.sort()
    starts = [c[0] for c in covered]
    for lo, hi in xr:
        code = img.read(lo, hi - lo)
        for p in range(len(code) - 5):
            if code[p] not in (0xe8, 0xe9):
                continue
            t = lo + p + 5 + struct.unpack_from('<i', code, p + 1)[0]
            if t in targets:
                site = lo + p
                j = bisect.bisect_right(starts, site) - 1
                if j >= 0 and covered[j][0] <= site < covered[j][1]:
                    continue
                print('%#x %#x raw %s' % (t, site, 'call' if code[p] == 0xe8 else 'jmp'))


if __name__ == '__main__':
    main()
