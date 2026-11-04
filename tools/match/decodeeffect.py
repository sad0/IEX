"""Facts for the IEX "unknown opcode -> inert CGameEffect" hook (BG2EE 2.7.3, Linux ELF + Windows PE).

Usage:
  python -I decodeeffect.py <BaldursGateII> <Baldur.exe> [--json out.json]
Prints, for both builds:
  - the DecodeEffect opcode jump table: which opcodes 0..367 fall to the NULL default
    (the default writes NULL+0x150, so those opcodes crash exactly like opcodes >= 368);
  - every direct `call rel32` (E8) site of CGameEffect::DecodeEffect (raw scan of executable sections);
  - the CGameEffect base vtable slots.
--json writes {"linux": {...}, "win": {...}} with the call-site RVAs/VAs (no game data).
Addresses are hard-wired for 2.7.3 (see docs/EFFECTS_DECODE.md); the tool re-checks them.
"""
import json
import struct
import sys

sys.path.insert(0, __import__('os').path.dirname(__file__))
from pedis import PE  # noqa: E402
from xrefs import ELF, pe_exec_ranges  # noqa: E402

LIN = dict(decode=0x1d5c20, bound=0x1d5c51, table_lea=0x1d5c5b, default=(0x1d5c70,),
           vtable=0xcbccd0, nslots=12)
WIN = dict(decode=0x1de3d0, bound=0x1de3fc, table=0x1e2770, default=(0x1e2730, 0x1e2735),
           vtable=0x58f020, nslots=11)
NOPS = 0x170  # cmp opcode, 0x16f ; ja default


def e8_sites(img, ranges, target, base=0):
    out = []
    for lo, hi in ranges:
        code = img.read(lo, hi - lo)
        p = code.find(b'\xe8')
        while p != -1 and p <= len(code) - 5:
            if lo + p + 5 + struct.unpack_from('<i', code, p + 1)[0] == target:
                out.append(lo + p)
            p = code.find(b'\xe8', p + 1)
    return out


def main():
    a = sys.argv[1:]
    elf, pe = ELF(a[0]), PE(a[1])
    res = {}

    # Linux: lea rdx,[rip+X] ; movsxd rax,[rdx+rax*4] ; add rax,rdx  (relative table)
    lea = elf.read(LIN['table_lea'], 7)
    assert lea[:3] == b'\x48\x8d\x15', 'linux table lea moved'
    tbl = LIN['table_lea'] + 7 + struct.unpack_from('<i', lea, 3)[0]
    raw = elf.read(tbl, NOPS * 4)
    lt = [tbl + struct.unpack_from('<i', raw, 4 * i)[0] for i in range(NOPS)]
    ldef = [i for i, t in enumerate(lt) if t in LIN['default']]
    # Windows: table of image-relative dwords
    raw = pe.read(WIN['table'], NOPS * 4)
    wt = [struct.unpack_from('<I', raw, 4 * i)[0] for i in range(NOPS)]
    wdef = [i for i, t in enumerate(wt) if t in WIN['default']]
    print('NULL-default opcodes < 0x170: linux', ldef, '\n                              win  ', wdef)

    lsites = e8_sites(elf, elf.exec_ranges(), LIN['decode'])
    wsites = e8_sites(pe, pe_exec_ranges(pe), WIN['decode'])
    print('E8 call sites: linux %d, win %d' % (len(lsites), len(wsites)))

    lv = [struct.unpack_from('<Q', elf.read(LIN['vtable'] + 8 * i, 8))[0] for i in range(LIN['nslots'])]
    wv = [struct.unpack_from('<Q', pe.read(WIN['vtable'] + 8 * i, 8))[0] - pe.base for i in range(WIN['nslots'])]
    print('base vtable linux', [hex(x) for x in lv])
    print('base vtable win  ', [hex(x) for x in wv])

    res['linux'] = dict(null_default_opcodes=ldef, callsites=[hex(x) for x in lsites], vtable=[hex(x) for x in lv])
    res['win'] = dict(null_default_opcodes=wdef, callsites=[hex(x) for x in wsites], vtable=[hex(x) for x in wv])
    if '--json' in a:
        with open(a[a.index('--json') + 1], 'w', encoding='utf-8', newline='\n') as fh:
            json.dump(res, fh, indent=1)


if __name__ == '__main__':
    main()
