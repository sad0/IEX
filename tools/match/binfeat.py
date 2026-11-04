"""Per-function feature extraction for ELF (symbolized) and PE (function list from Ghidra) x86-64 binaries.

Features per function (ordered where it matters):
  calls  : ordered list of call targets: ('f', rva) direct call/tail-jump to a function, ('i', name) import
  strs   : ordered list of string literals referenced (RIP-relative lea/mov)
  frefs  : function addresses taken (lea of a function entry, callbacks)
  drefs  : RIP-relative data addresses (non-string)
  flts   : float/double constants loaded from memory
  imms   : notable immediates (|x| >= 0x100, not address-like)
  nins, nbb, size

Usage as a library: load_elf(path, symjson) / load_pe(path, ghidra_jsonl) -> Binary
CLI: python -I binfeat.py elf <elf> <symbols.json> <out.pkl>
     python -I binfeat.py pe  <exe> <functions.jsonl> <out.pkl>
"""
import json
import pickle
import struct
import sys

import capstone
from capstone import x86

PRINTABLE = set(range(0x20, 0x7f)) | {9, 10, 13}


class Binary:
    def __init__(self):
        self.segs = []          # (va, size, bytes|None, name, exec)
        self.ptrs = {}          # va -> pointer value (relocated / absolute), RVA space
        self.imports = {}       # va of slot or stub -> import name
        self.funcs = {}         # entry rva -> dict(name, ranges)
        self.feat = {}          # entry rva -> features
        self.objects = {}       # rva -> (name, size)   (ELF only)
        self.kind = ''

    def seg_of(self, va):
        for s in self.segs:
            if s[0] <= va < s[0] + s[1]:
                return s
        return None

    def read(self, va, n):
        s = self.seg_of(va)
        if not s or s[2] is None:
            return None
        o = va - s[0]
        return s[2][o:o + n]

    def cstr(self, va, maxlen=1024):
        s = self.seg_of(va)
        if not s or s[2] is None or s[4]:
            return None
        o = va - s[0]
        e = s[2].find(b'\0', o, o + maxlen)
        if e < 0:
            return None
        b = s[2][o:e]
        if len(b) < 2 or any(c not in PRINTABLE for c in b):
            return None
        return b.decode('latin-1')

    def ptr(self, va):
        if va in self.ptrs:
            return self.ptrs[va]
        b = self.read(va, 8)
        if not b or len(b) < 8:
            return None
        v = struct.unpack('<Q', b)[0]
        return v - self.base_abs if self.base_abs and v >= self.base_abs else v

    base_abs = 0


# ---------------------------------------------------------------- ELF

def _elf_sections(d):
    shoff, = struct.unpack_from('<Q', d, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', d, 0x3A)
    secs = [struct.unpack_from('<IIQQQQIIQQ', d, shoff + i * shentsize) for i in range(shnum)]
    so = secs[shstrndx][4]
    named = []
    for s in secs:
        n = d[so + s[0]:d.index(b'\0', so + s[0])].decode()
        named.append((n, s))
    return named


def load_elf(path, symjson):
    d = open(path, 'rb').read()
    b = Binary()
    b.kind = 'elf'
    secs = _elf_sections(d)
    by = {n: s for n, s in secs}
    for n, s in secs:
        typ, flags, va, off, size = s[1], s[2], s[3], s[4], s[5]
        if not (flags & 2) or va == 0:  # SHF_ALLOC
            continue
        data = None if typ == 8 else d[off:off + size]
        b.segs.append((va, size, data, n, bool(flags & 4)))
    # dynamic symbols
    dsy = by['.dynsym']
    dstr = by['.dynstr']
    dnames = []
    for i in range(dsy[5] // 24):
        nm, = struct.unpack_from('<I', d, dsy[4] + i * 24)
        dnames.append(d[dstr[4] + nm:d.index(b'\0', dstr[4] + nm)].decode())
    got_names = {}
    for rn in ('.rela.dyn', '.rela.plt'):
        r = by[rn]
        for i in range(r[5] // 24):
            off, info, add = struct.unpack_from('<QQq', d, r[4] + i * 24)
            typ, sym = info & 0xffffffff, info >> 32
            if typ == 8:  # RELATIVE
                b.ptrs[off] = add
            elif typ in (6, 7, 1) and sym:  # GLOB_DAT, JUMP_SLOT, 64
                got_names[off] = dnames[sym]
    # PLT stubs: find jmp [rip+X]
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True
    for pn, al in (('.plt', 16), ('.plt.sec', 16), ('.plt.got', 8)):
        if pn not in by:
            continue
        s = by[pn]
        for ins in md.disasm(d[s[4]:s[4] + s[5]], s[3]):
            if ins.mnemonic == 'jmp' and ins.operands and ins.operands[0].type == x86.X86_OP_MEM \
                    and ins.operands[0].mem.base == x86.X86_REG_RIP:
                slot = ins.address + ins.size + ins.operands[0].mem.disp
                if slot in got_names:
                    # stub start = 16-byte aligned entry
                    b.imports[s[3] + ((ins.address - s[3]) & ~(al - 1))] = got_names[slot]
    for slot, n in got_names.items():
        b.imports[slot] = n
    j = json.load(open(symjson, encoding='utf-8'))
    cold = []
    for f in j['functions']:
        a = int(f['addr'], 16)
        if '.cold' in f['name']:
            cold.append((f['name'].split('.cold')[0], a, f['size']))
            continue
        if a in b.funcs:
            b.funcs[a].setdefault('aliases', []).append(f['name'])
            continue
        b.funcs[a] = {'name': f['name'], 'dem': f['demangled'], 'ranges': [(a, a + max(f['size'], 1))]}
    byname = {v['name']: k for k, v in b.funcs.items()}
    for parent, a, sz in cold:
        p = byname.get(parent)
        if p is not None:
            b.funcs[p]['ranges'].append((a, a + sz))
    # static (local) functions are absent from .symtab: recover them from .eh_frame FDEs as unnamed pseudo-functions
    known = set(b.funcs) | {a for _, a, _ in cold}
    for a, sz in eh_frame_fdes(d, by['.eh_frame']):
        if a not in known and sz > 0 and by['.text'][3] <= a < by['.text'][3] + by['.text'][5]:
            b.funcs[a] = {'name': f'sub_{a:x}', 'dem': f'sub_{a:x}', 'ranges': [(a, a + sz)], 'static': True}
    for o in j.get('objects', []):
        b.objects[int(o['addr'], 16)] = (o['name'], o['size'], o['demangled'])
    return b


def _uleb(d, p):
    r = sh = 0
    while True:
        c = d[p]
        p += 1
        r |= (c & 0x7f) << sh
        sh += 7
        if c < 0x80:
            return r, p


def eh_frame_fdes(d, sec):
    """Yield (pc_begin, pc_range) for every FDE in .eh_frame (GCC: CIE 'zR', pcrel|sdata4 pointers)."""
    off, va, size = sec[4], sec[3], sec[5]
    p, end = off, off + size
    cie_enc = {}
    while p < end:
        ln, = struct.unpack_from('<I', d, p)
        if ln == 0:
            break
        q = p + 4
        cid, = struct.unpack_from('<I', d, q)
        if cid == 0:  # CIE
            aug_p = q + 5
            aug = d[aug_p:d.index(bytes(1), aug_p)].decode()
            r = d.index(bytes(1), aug_p) + 1
            _, r = _uleb(d, r)          # code align
            _, r = _uleb(d, r)          # data align (sleb, same length)
            r += 1                      # return register (version 1: one byte)
            enc = 0
            if aug.startswith('z'):
                _, r = _uleb(d, r)
                for ch in aug[1:]:
                    if ch == 'R':
                        enc = d[r]
                        r += 1
                    elif ch == 'P':
                        penc = d[r]
                        r += 1 + (4 if (penc & 0xf) in (3, 0xb) else 8)
                    elif ch == 'L':
                        r += 1
            cie_enc[p] = enc
        else:
            cie = q - cid
            enc = cie_enc.get(cie, 0x1b)
            fp = q + 4
            if (enc & 0xf) == 0xb:
                v, rg = struct.unpack_from('<ii', d, fp)
            else:
                v, rg = struct.unpack_from('<qq', d, fp)
            if enc & 0x70 == 0x10:
                v += va + (fp - off)
            yield v, rg
        p += 4 + ln


# ---------------------------------------------------------------- PE

def load_pe(path, fnjsonl):
    d = open(path, 'rb').read()
    b = Binary()
    b.kind = 'pe'
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    nsec, = struct.unpack_from('<H', d, pe + 6)
    optsz, = struct.unpack_from('<H', d, pe + 20)
    opt = pe + 24
    imagebase, = struct.unpack_from('<Q', d, opt + 24)
    b.base_abs = imagebase
    ddir = opt + 112
    sh = opt + optsz
    for i in range(nsec):
        name = d[sh + i * 40:sh + i * 40 + 8].rstrip(b'\0').decode()
        vsize, va, rsize, roff = struct.unpack_from('<IIII', d, sh + i * 40 + 8)
        ch, = struct.unpack_from('<I', d, sh + i * 40 + 36)
        data = d[roff:roff + min(rsize, vsize)] + b'\0' * max(0, vsize - rsize)
        b.segs.append((va, vsize, data, name, bool(ch & 0x20000000)))

    def rd(rva, n):
        return b.read(rva, n)

    imp_rva, imp_size = struct.unpack_from('<II', d, ddir + 8)
    i = 0
    while True:
        desc = rd(imp_rva + i * 20, 20)
        oft, _, _, nm, ft = struct.unpack('<IIIII', desc)
        if not ft:
            break
        dll = b.cstr(nm) or '?'
        k = 0
        while True:
            th = struct.unpack('<Q', rd((oft or ft) + k * 8, 8))[0]
            if not th:
                break
            if th >> 63:
                n = f'{dll}#{th & 0xffff}'
            else:
                n = b.cstr((th & 0x7fffffff) + 2) or '?'
            b.imports[ft + k * 8] = n
            k += 1
        i += 1
    # base relocations -> pointer map
    rel_rva, rel_size = struct.unpack_from('<II', d, ddir + 5 * 8)
    p = rel_rva
    while p < rel_rva + rel_size:
        page, bsz = struct.unpack('<II', rd(p, 8))
        if bsz == 0:
            break
        for k in range((bsz - 8) // 2):
            e, = struct.unpack('<H', rd(p + 8 + 2 * k, 2))
            if e >> 12 == 10:
                va = page + (e & 0xfff)
                v, = struct.unpack('<Q', rd(va, 8))
                b.ptrs[va] = v - imagebase
        p += bsz
    if not b.ptrs:
        # relocations stripped (fixed image base): every 8-aligned qword inside the image is a pointer candidate
        lo, hi = imagebase, imagebase + max(sg[0] + sg[1] for sg in b.segs)
        for va, vsize, data, name, ex in b.segs:
            if ex or name in ('.pdata', '.rsrc'):
                continue
            for o in range(0, len(data) - 7, 8):
                v = struct.unpack_from('<Q', data, o)[0]
                if lo <= v < hi:
                    b.ptrs[va + o] = v - imagebase
    # exports (this build exports SDL2)
    b.exports = {}
    exp_rva, exp_size = struct.unpack_from('<II', d, ddir)
    if exp_rva:
        _, _, _, _, _, _, nf, nn, af, an, ao = struct.unpack('<IIHHIIIIIII', rd(exp_rva, 40))
        for k in range(nn):
            n = b.cstr(struct.unpack('<I', rd(an + 4 * k, 4))[0])
            o, = struct.unpack('<H', rd(ao + 2 * k, 2))
            t, = struct.unpack('<I', rd(af + 4 * o, 4))
            b.exports.setdefault(t, []).append(n)
    b.syms = []
    for line in open(fnjsonl, encoding='utf-8'):
        o = json.loads(line)
        if o['k'] == 'sym':
            b.syms.append((int(o['rva'], 16), o['name'], o['ns']))
            continue
        if o.get('ext'):
            continue
        a = int(o['rva'], 16)
        rs = [(int(x, 16), int(y, 16) + 1) for x, y in o['ranges']]
        b.funcs[a] = {'name': o['name'], 'ns': o['ns'], 'ranges': rs,
                      'thunk': int(o['thunk'], 16) if o['thunk'] else None}
    return b


# ---------------------------------------------------------------- features

def extract(b):
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True
    entries = b.funcs
    for n, (fa, fi) in enumerate(sorted(entries.items())):
        calls, strs, frefs, drefs, flts, imms, seq = [], [], [], [], [], [], []
        nins = nbb = 0
        size = 0
        inbody = fi['ranges']
        for (s, e) in inbody:
            size += e - s
            code = b.read(s, e - s)
            if not code:
                continue
            for ins in md.disasm(code, s):
                nins += 1
                m = ins.mnemonic
                if (m.startswith('j') and m != 'jmp') or m.startswith('loop'):
                    nbb += 1
                    continue
                ops = ins.operands
                if m == 'call' or m == 'jmp':
                    if ops and ops[0].type == x86.X86_OP_IMM:
                        t = ops[0].imm
                        if t in b.imports:
                            calls.append(('i', b.imports[t]))
                        elif t in entries and not (m == 'jmp' and any(x <= t < y for x, y in inbody)):
                            calls.append(('f', t))
                        continue
                    if ops and ops[0].type == x86.X86_OP_MEM and ops[0].mem.base == x86.X86_REG_RIP:
                        slot = ins.address + ins.size + ops[0].mem.disp
                        if slot in b.imports:
                            calls.append(('i', b.imports[slot]))
                        continue
                    continue
                for op in ops:
                    if op.type == x86.X86_OP_MEM and op.mem.base == x86.X86_REG_RIP:
                        t = ins.address + ins.size + op.mem.disp
                        if t in b.imports:
                            frefs.append(('i', b.imports[t]))
                            continue
                        if t in entries:
                            frefs.append(('f', t))
                            seq.append(('r', t))
                            continue
                        st = b.cstr(t) if m in ('lea', 'mov') else None
                        if st is not None:
                            strs.append(st)
                            seq.append(('s', st))
                            continue
                        sg = b.seg_of(t)
                        if sg and sg[2] is not None and not sg[4] and op.size in (4, 8) and \
                                (m.startswith(('movs', 'adds', 'subs', 'muls', 'divs', 'comis', 'ucomis', 'maxs', 'mins', 'cvt'))):
                            raw = b.read(t, op.size)
                            if raw and len(raw) == op.size:
                                v = struct.unpack('<f' if op.size == 4 else '<d', raw)[0]
                                flts.append(float('%.6g' % v) if v == v else 0.0)
                                continue
                        drefs.append(t)
                    elif op.type == x86.X86_OP_IMM:
                        v = op.imm
                        if 0x100 <= abs(v) < 0x10000000 and m not in ('call', 'jmp'):
                            imms.append(v & 0xffffffff)
        b.feat[fa] = {'calls': calls, 'strs': strs, 'frefs': frefs, 'drefs': drefs, 'flts': flts,
                      'imms': imms, 'seq': seq, 'nins': nins, 'nbb': nbb, 'size': size}
        if n % 2000 == 0:
            print(f'  {n}/{len(entries)}', file=sys.stderr)


def main():
    kind, path, meta, out = sys.argv[1:5]
    b = load_elf(path, meta) if kind == 'elf' else load_pe(path, meta)
    print(f'{kind}: {len(b.funcs)} functions, {len(b.imports)} imports, {len(b.ptrs)} pointers', file=sys.stderr)
    extract(b)
    with open(out, 'wb') as f:
        pickle.dump(b, f, protocol=4)


if __name__ == '__main__':
    import binfeat  # so pickled objects reference binfeat.Binary, not __main__.Binary
    binfeat.main()
