"""Grep the disassembly of every function of a PE x64 image.

Usage: python -I pegrep.py <exe> <win_functions.jsonl> <regex> [--range lo-hi] [--max N]
  Disassembles each function body listed in win_functions.jsonl (Win_ExportFunctions.java output)
  and prints "<funcRVA> <insnRVA>: <mnemonic> <operands>" for instructions whose text matches
  <regex> (Python re, searched in "mnemonic operands"). RIP-relative operands are shown as
  "[rva 0x...]" so data/vtable RVAs can be grepped, e.g.  'lea .*\\[rva 0x58f670\\]'  or
  'mov byte ptr \\[r\\w+ \\+ 8\\], 0x41'.
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
    exe, fj, rx = a[0], a[1], re.compile(a[2])
    lo, hi, mx = 0, 1 << 40, 1 << 30
    if '--range' in a:
        r = a[a.index('--range') + 1].split('-')
        lo, hi = int(r[0], 16), int(r[1], 16)
    if '--max' in a:
        mx = int(a[a.index('--max') + 1])
    pe = PE(exe)
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True
    n = 0
    for line in open(fj):
        f = json.loads(line)
        if f.get('k') != 'fn' or f.get('thunk'):
            continue
        frva = int(f['rva'], 16)
        if not lo <= frva < hi:
            continue
        for s, e in f['ranges']:
            s, e = int(s, 16), int(e, 16)
            code = pe.read(s, e - s + 1)
            for ins in md.disasm(code, pe.base + s):
                ops = ins.op_str
                for op in ins.operands:
                    if op.type == x86.X86_OP_MEM and op.mem.base == x86.X86_REG_RIP:
                        t = ins.address + ins.size + op.mem.disp - pe.base
                        ops = re.sub(r'\[rip [+-] 0x[0-9a-f]+\]', '[rva %#x]' % t, ops)
                if ins.mnemonic in ('call', 'jmp') and ins.operands and ins.operands[0].type == x86.X86_OP_IMM:
                    ops = 'rva %#x' % (ins.operands[0].imm - pe.base)
                txt = '%s %s' % (ins.mnemonic, ops)
                if rx.search(txt):
                    print('%#x %#x: %s' % (frva, ins.address - pe.base, txt))
                    n += 1
                    if n >= mx:
                        return


if __name__ == '__main__':
    main()
