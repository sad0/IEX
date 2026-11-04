"""Read Itanium C++ RTTI (typeinfo base classes) and vtable info from an ELF x86_64 PIE binary.

Usage: python -I rtti.py <elf> <symbols.json> <Class> [<Class> ...]

For each class prints JSON: {class: {vtable, vtable_size, vtable_addr_point, typeinfo, kind, bases}}
  - addresses are ELF symtab VAs (image-relative; same as symbols.json)
  - kind: class (no bases), si (single inheritance), vmi (multiple/virtual)
  - bases: [{name, offset}] (offset = base subobject offset, from __offset_flags >> 8)
Pointers inside .data.rel.ro are resolved through .rela.dyn (R_X86_64_RELATIVE addends,
R_X86_64_64 symbol relocations for the __cxxabiv1 type_info vtables).
"""
import json
import struct
import sys

R_X86_64_64 = 1
R_X86_64_RELATIVE = 8


def sections(d):
    shoff, = struct.unpack_from('<Q', d, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', d, 0x3A)
    secs = [struct.unpack_from('<IIQQQQIIQQ', d, shoff + i * shentsize) for i in range(shnum)]
    stro = secs[shstrndx][4]

    def nm(o):
        return d[stro + o:d.index(b'\0', stro + o)].decode()

    return secs, {nm(s[0]): s for s in secs}


def main():
    elf, symjson, classes = sys.argv[1], sys.argv[2], sys.argv[3:]
    d = open(elf, 'rb').read()
    secs, by = sections(d)

    # VA -> file offset via section table (alloc sections with file data)
    alloc = [(s[3], s[5], s[4]) for s in secs if s[3] and s[1] != 8]  # addr, size, offset (skip NOBITS)

    def off(va):
        for a, sz, o in alloc:
            if a <= va < a + sz:
                return o + (va - a)
        return None

    # dynamic symbols for R_X86_64_64
    dynsym, dynstr = by['.dynsym'], by['.dynstr']

    def dsym(i):
        st_name, = struct.unpack_from('<I', d, dynsym[4] + i * 24)
        o = dynstr[4] + st_name
        return d[o:d.index(b'\0', o)].decode()

    rel = {}
    for name in ('.rela.dyn',):
        s = by.get(name)
        if not s:
            continue
        for i in range(s[5] // 24):
            r_off, r_info, r_add = struct.unpack_from('<QQq', d, s[4] + i * 24)
            typ, sym = r_info & 0xffffffff, r_info >> 32
            if typ == R_X86_64_RELATIVE:
                rel[r_off] = ('rel', r_add)
            elif typ == R_X86_64_64:
                rel[r_off] = ('sym', dsym(sym), r_add)

    def ptr(va):
        if va in rel:
            return rel[va]
        o = off(va)
        return ('raw', struct.unpack_from('<Q', d, o)[0])

    S = json.load(open(symjson))
    objs = S['objects']
    by_dem = {o['demangled']: o for o in objs}
    by_addr = {}
    for o in objs:
        by_addr.setdefault(int(o['addr'], 16), o['demangled'])

    out = {}
    for c in classes:
        ti = by_dem.get('typeinfo for ' + c)
        vt = by_dem.get('vtable for ' + c)
        e = {}
        if vt:
            e['vtable'] = vt['addr']
            e['vtable_size'] = vt['size']
            e['vtable_addr_point'] = hex(int(vt['addr'], 16) + 16)
        if ti:
            a = int(ti['addr'], 16)
            e['typeinfo'] = ti['addr']
            p0 = ptr(a)
            kname = p0[1] if p0[0] == 'sym' else str(p0)
            if '__si_class_type_info' in kname:
                e['kind'] = 'si'
                b = ptr(a + 16)
                e['bases'] = [{'name': by_addr.get(b[1], hex(b[1])).replace('typeinfo for ', ''), 'offset': '0x0'}]
            elif '__vmi_class_type_info' in kname:
                e['kind'] = 'vmi'
                o = off(a + 16)
                flags, cnt = struct.unpack_from('<II', d, o)
                bases = []
                for i in range(cnt):
                    b = ptr(a + 24 + i * 16)
                    of, = struct.unpack_from('<q', d, off(a + 32 + i * 16))
                    bases.append({'name': by_addr.get(b[1], hex(b[1])).replace('typeinfo for ', ''),
                                  'offset': hex(of >> 8), 'virtual': bool(of & 1), 'public': bool(of & 2)})
                e['bases'] = bases
            else:
                e['kind'] = 'class'
                e['bases'] = []
        out[c] = e
    print(json.dumps(out, indent=1))


if __name__ == '__main__':
    main()
