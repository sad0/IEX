"""List "operator new(N)" call sites of a PE x64 image with the constructor called on the result.

Usage: python -I newsites.py <exe> <win_functions.jsonl> <operatorNewRVA> [--size 0xN] [--ctor 0xRVA]
Output: "<size> <ctorRVA|-> <vtableRVA|-> caller=<funcRVA>@<siteRVA>"
  size   : immediate loaded into ECX/RCX before the call (MSVC x64: first argument)
  ctor   : first direct call after the allocation whose RCX is the returned pointer (mov rcx, rax)
  vtable : when the ctor is inlined, first "lea reg, [rip+X]" stored to [rax]/[rbx]... in the next
           40 instructions (vtable candidate)
Histogram per ctor = sizeof candidates (most frequent wins; outliers are wrapper structs).
"""
import json
import re
import sys

import capstone
from capstone import x86

sys.path.insert(0, __import__('os').path.dirname(__file__))
from pedis import PE  # noqa: E402


def main():
    a = sys.argv[1:]
    pe = PE(a[0])
    opnew = int(a[2], 16)
    want_size = int(a[a.index('--size') + 1], 16) if '--size' in a else None
    want_ctor = int(a[a.index('--ctor') + 1], 16) if '--ctor' in a else None
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True
    for line in open(a[1]):
        f = json.loads(line)
        if f.get('k') != 'fn' or f.get('thunk'):
            continue
        for s, e in f['ranges']:
            s, e = int(s, 16), int(e, 16)
            insns = list(md.disasm(pe.read(s, e - s + 1), pe.base + s))
            for i, ins in enumerate(insns):
                if ins.mnemonic != 'call' or not ins.operands or ins.operands[0].type != x86.X86_OP_IMM:
                    continue
                if ins.operands[0].imm - pe.base != opnew:
                    continue
                size = None
                for j in range(i - 1, max(i - 8, -1), -1):
                    p = insns[j]
                    if p.mnemonic == 'mov' and p.op_str.split(',')[0] in ('ecx', 'rcx'):
                        m = re.match(r'(?:ecx|rcx), (0x[0-9a-f]+|\d+)$', p.op_str)
                        size = int(m.group(1), 0) if m else None
                        break
                    if p.mnemonic == 'call':
                        break
                ctor = vt = None
                rax_alias = {'rax'}
                for k in range(i + 1, min(i + 40, len(insns))):
                    q = insns[k]
                    if q.mnemonic == 'mov' and q.op_str.startswith('r') and ', rax' in q.op_str and len(q.operands) == 2 \
                            and q.operands[1].type == x86.X86_OP_REG:
                        rax_alias.add(q.op_str.split(',')[0])
                    if q.mnemonic == 'lea' and q.operands[1].type == x86.X86_OP_MEM and \
                            q.operands[1].mem.base == x86.X86_REG_RIP and vt is None:
                        t = q.address + q.size + q.operands[1].mem.disp - pe.base
                        # only keep it if stored to [alias] next
                        reg = q.op_str.split(',')[0]
                        for r in insns[k + 1:k + 6]:
                            if r.mnemonic == 'mov' and re.match(r'qword ptr \[(\w+)\], ' + reg + '$', r.op_str) and \
                                    re.match(r'qword ptr \[(\w+)\]', r.op_str).group(1) in rax_alias:
                                vt = t
                                break
                    if q.mnemonic == 'call':
                        if q.operands[0].type == x86.X86_OP_IMM:
                            ctor = q.operands[0].imm - pe.base
                        break
                if want_size is not None and size != want_size:
                    continue
                if want_ctor is not None and ctor != want_ctor:
                    continue
                print('%s %s %s caller=%#x@%#x' % (hex(size) if size is not None else '?',
                                                   hex(ctor) if ctor is not None else '-',
                                                   hex(vt) if vt is not None else '-',
                                                   int(f['rva'], 16), ins.address - pe.base))


if __name__ == '__main__':
    main()
