"""Print the exception, registers and module-relative return addresses of a Windows minidump.

Usage: python -I minidump.py <file.dmp> [module filter substrings...]
Used to diagnose game crashes in IEX test copies without a debugger.
"""
import struct
import sys


def main():
    path = sys.argv[1]
    filters = sys.argv[2:] or ['Baldur', 'IEX']
    d = open(path, 'rb').read()
    _, _, nstreams, dirrva = struct.unpack_from('<IIII', d, 0)
    streams = {}
    for i in range(nstreams):
        t, size, rva = struct.unpack_from('<III', d, dirrva + i * 12)
        streams[t] = (size, rva)

    _, rva = streams[4]  # ModuleListStream
    mods = []
    for i in range(struct.unpack_from('<I', d, rva)[0]):
        o = rva + 4 + i * 108
        base, size = struct.unpack_from('<QI', d, o)
        name_rva = struct.unpack_from('<I', d, o + 20)[0]
        length = struct.unpack_from('<I', d, name_rva)[0]
        name = d[name_rva + 4:name_rva + 4 + length].decode('utf-16le')
        mods.append((base, size, name.replace(chr(92), '/').split('/')[-1]))

    def where(a):
        for base, size, name in mods:
            if base <= a < base + size:
                return f'{name}+{a - base:#x}'
        return hex(a)

    _, rva = streams[6]  # ExceptionStream
    code, _, _, addr, nparams = struct.unpack_from('<IIQQI', d, rva + 8)
    params = struct.unpack_from('<15Q', d, rva + 8 + 32)[:nparams]
    print('exception', hex(code), 'at', where(addr), 'params', [hex(x) for x in params])
    _, ctx = struct.unpack_from('<II', d, rva + 8 + 152)
    names = ['rax', 'rcx', 'rdx', 'rbx', 'rsp', 'rbp', 'rsi', 'rdi', 'r8', 'r9', 'r10', 'r11', 'r12', 'r13', 'r14', 'r15']
    regs = dict(zip(names, struct.unpack_from('<16Q', d, ctx + 0x78)))
    print('rip', where(struct.unpack_from('<Q', d, ctx + 0xf8)[0]))
    print(' '.join(f'{k}={v:#x}' for k, v in regs.items()))

    if 9 in streams:  # Memory64ListStream: scan the stack for return addresses
        _, rva = streams[9]
        count, data = struct.unpack_from('<QQ', d, rva)
        rsp = regs['rsp']
        for i in range(count):
            start, size = struct.unpack_from('<QQ', d, rva + 16 + i * 16)
            if start <= rsp < start + size:
                o = data + (rsp - start)
                hits = []
                for k in range(0, min(0x800, start + size - rsp), 8):
                    w = where(struct.unpack_from('<Q', d, o + k)[0])
                    if any(f in w for f in filters):
                        hits.append(f'+{k:#x}:{w}')
                print('stack:', ' '.join(hits[:30]))
                break
            data += size


if __name__ == '__main__':
    main()
