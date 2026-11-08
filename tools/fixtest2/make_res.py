"""Test resources for tools/fixtest2 (engine fixes of IEX 0.4.1; our own data, written into a test copy's override).

Usage: python -I make_res.py <override dir> <mode>
  IXFXB.EFF    opcode 22 LUCK +2 (what the op182 / op183 test effects apply)
  IX182N.EFF   opcode 182: item IXNOITEM (nobody has it) -> IXFXB, 600 s
  IX183N.EFF   opcode 183: item type 0x60 (no item has it) -> IXFXB, 600 s
  XPLIST.2DA   columns 0-100 (level), row IXQ1 = P_<600 * level> (AddXP2DA("IXQ1") shows the average party level)
  IXFX2DA.2DA  TakeItemListParty list: rows A, B (indented: MISC01), C, a line of spaces, D (AMUL01)
  M_FX2CFG.lua FX2_MODE = <mode> (main | op248 | startup2da | rest)
  mode startup2da also writes WSPECIAL.2DA with row 3 indented (a rules table loaded at startup)
"""
import os
import struct
import sys


def eff(opcode, param1=0, param2=0, timing=0, duration=0, res=b'', res2=b'', target=1):
    b = bytearray(0x110)
    b[0:8] = b'EFF V2.0'
    b[8:16] = b'EFF V2.0'
    struct.pack_into('<IIIiII', b, 0x10, opcode, target, 0, param1, param2, timing)
    struct.pack_into('<I', b, 0x28, duration)
    struct.pack_into('<HH', b, 0x2c, 100, 0)
    b[0x30:0x30 + len(res)] = res
    b[0x70:0x70 + len(res2)] = res2
    for off in (0x88, 0x8c, 0x90, 0x94):
        struct.pack_into('<i', b, off, -1)   # source / target x, y unset
    return bytes(b)


# AddXP2DA reads XPLIST at column = average party level, row = the quest name
XPLIST = ('2DA V1.0\r\n0\r\n        ' + ' '.join(str(lv) for lv in range(0, 101)) + '\r\n'
          + 'IXQ1    ' + ' '.join('P_%d' % (lv * 600) for lv in range(0, 101)) + '\r\n').encode()

# A, then B indented (the engine's row count skipped it, its fill pass did not), C, a line of spaces (skipped by the
# count, a row index for the fill), then D: the fill writes D one or two rows past the counted 3.
LIST2DA = (b'2DA V1.0\r\n*\r\n        RESREF\r\n'
           b'A       IXNONE1\r\n'
           b'    B   MISC01\r\n'
           b'C       IXNONE2\r\n'
           b'        \r\n'
           b'D       AMUL01\r\n')

WSPECIAL = (b'2DA V1.0\r\n0\r\n   HIT  DAMAGE  SPEED\r\n0   0     0       0\r\n1   0     0       0\r\n'
            b'2   1     2       0\r\n   3   3     3       0\r\n4   3     4       -1\r\n5   3     5       -3\r\n')


def main():
    od, mode = sys.argv[1], sys.argv[2]
    files = {
        'IXFXB.EFF': eff(22, 2, 0, 0, 300),
        'IX182N.EFF': eff(182, 0, 0, 0, 600, b'IXNOITEM', b'IXFXB'),
        'IX183N.EFF': eff(183, 0, 0x60, 0, 600, b'IXFXB'),
        'XPLIST.2DA': XPLIST,
        'IXFX2DA.2DA': LIST2DA,
        'M_FX2CFG.lua': ('FX2_MODE = %r\n' % mode).encode(),
    }
    for n in os.listdir(od):
        if n.lower() == 'wspecial.2da':
            os.remove(os.path.join(od, n))
    if mode == 'startup2da':
        files['WSPECIAL.2DA'] = WSPECIAL
    for name, data in files.items():
        # both cases for a case-sensitive file system (Linux); M_ files keep their name
        names = {name} if name.startswith('M_') else {name, name.lower()}
        for n in names:
            with open(os.path.join(od, n), 'wb') as fh:
                fh.write(data)
    print('wrote', ', '.join(files))


if __name__ == '__main__':
    main()
