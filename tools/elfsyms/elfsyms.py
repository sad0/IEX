"""Dump the .symtab of an IE EE Linux binary into a JSON symbol table.

Usage: python -I elfsyms.py <elf> <out.json> [--cxxfilt <path to llvm-cxxfilt/c++filt>]

Output: {"binary": ..., "build_id": ..., "functions": [{"name", "demangled", "addr", "size"}],
         "objects": [...same...]}
Addresses are virtual addresses as stored in the ELF (the image is PIE, so they are image-relative).
"""
import json
import struct
import subprocess
import sys


def read_sections(d):
    shoff, = struct.unpack_from('<Q', d, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', d, 0x3A)
    secs = [struct.unpack_from('<IIQQQQIIQQ', d, shoff + i * shentsize) for i in range(shnum)]
    strtab_off = secs[shstrndx][4]

    def name(o):
        return d[strtab_off + o:d.index(b'\0', strtab_off + o)].decode()

    return secs, {name(s[0]): s for s in secs}


def build_id(d, by_name):
    s = by_name.get('.note.gnu.build-id')
    if not s:
        return None
    off = s[4]
    namesz, descsz, _ = struct.unpack_from('<III', d, off)
    desc = off + 12 + ((namesz + 3) & ~3)
    return d[desc:desc + descsz].hex()


def demangle(names, cxxfilt):
    if not cxxfilt:
        return names
    out = subprocess.run([cxxfilt], input='\n'.join(names), capture_output=True, text=True, check=True).stdout
    res = out.splitlines()
    return res if len(res) == len(names) else names


def main():
    args = sys.argv[1:]
    cxxfilt = None
    if '--cxxfilt' in args:
        i = args.index('--cxxfilt')
        cxxfilt = args[i + 1]
        del args[i:i + 2]
    elf, out = args
    d = open(elf, 'rb').read()
    if d[:4] != b'\x7fELF' or d[4] != 2:
        sys.exit('not an ELF64 file')
    secs, by_name = read_sections(d)
    if '.symtab' not in by_name:
        sys.exit('no .symtab (stripped binary)')
    st = by_name['.symtab']
    strt = secs[st[6]]
    funcs, objs = [], []
    for i in range(st[5] // 24):
        n, info, _, shn, val, size = struct.unpack_from('<IBBHQQ', d, st[4] + i * 24)
        if not val or shn == 0:
            continue
        nm = d[strt[4] + n:d.index(b'\0', strt[4] + n)].decode(errors='replace')
        kind = info & 15
        if kind == 2:
            funcs.append([nm, val, size])
        elif kind == 1:
            objs.append([nm, val, size])
    result = {'binary': elf.replace('\\', '/').split('/')[-1], 'build_id': build_id(d, by_name)}
    for key, items in (('functions', funcs), ('objects', objs)):
        items.sort(key=lambda x: x[1])
        dem = demangle([x[0] for x in items], cxxfilt)
        result[key] = [{'name': x[0], 'demangled': dm, 'addr': hex(x[1]), 'size': x[2]} for x, dm in zip(items, dem)]
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(result, f, indent=1)
    print(f"{len(funcs)} functions, {len(objs)} objects -> {out}")


if __name__ == '__main__':
    main()
