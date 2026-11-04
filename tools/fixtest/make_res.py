"""Test resources for tools/fixtest (our own data, written into the test copy's override only).

Usage: python -I make_res.py <override dir>
  IXFXB.EFF    opcode 22 LUCK +2 (what the opcode 182 tests apply)
  IXFX182M.EFF opcode 182: item IXNOITEM (nobody has it) -> IXFXB
  IXFX182A.EFF opcode 182: item AMUL01 (equipped in the amulet slot by the probe) -> IXFXB
  IXSPLP.SPL   one ability, opcode 22 LUCK +1 on the target (SPLPROT and immunity-message tests)
  SPLPROT.2DA  the copy's own table + row IXFXT: STAT(LUCK) >= 5; M_FXTROW.lua gives the probe its index
  HPWAR.2DA    1d1+5 per level (the HP-table modifier test), same for HPWIZ / HPROGUE / HPPRS / HPMONK / HPBARB
  WSPECIAL.2DA SPEED -10 on proficiency levels 1-5 (the weapon-speed test: speed factor 0 after the fix)
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
    struct.pack_into('<i', b, 0x88, -1)   # source x/y unset
    struct.pack_into('<i', b, 0x8c, -1)
    struct.pack_into('<i', b, 0x90, -1)
    struct.pack_into('<i', b, 0x94, -1)
    return bytes(b)


def spl(effects):
    hdr = bytearray(0x72)
    hdr[0:8] = b'SPL V1  '
    struct.pack_into('<ii', hdr, 0x08, -1, -1)       # names
    struct.pack_into('<H', hdr, 0x1c, 1)             # wizard spell
    struct.pack_into('<I', hdr, 0x34, 1)             # level 1
    struct.pack_into('<IH', hdr, 0x64, 0x72, 1)      # 1 ability at 0x72
    struct.pack_into('<IHH', hdr, 0x6a, 0x72 + 0x28, 0, 0)
    ab = bytearray(0x28)
    struct.pack_into('<BBH', ab, 0x00, 1, 0, 4)      # type 1, location 4 (spell)
    struct.pack_into('<BB', ab, 0x0c, 1, 0)          # target: creature
    struct.pack_into('<HH', ab, 0x0e, 30, 1)         # range, min level
    struct.pack_into('<HH', ab, 0x1e, len(effects), 0)
    struct.pack_into('<H', ab, 0x26, 1)              # projectile: none
    out = bytes(hdr) + bytes(ab)
    for opcode, param1, param2, timing, duration in effects:
        e = bytearray(0x30)
        struct.pack_into('<HBBiIBBI', e, 0, opcode, 2, 0, param1, param2, timing, 0, duration)
        struct.pack_into('<BB', e, 0x12, 100, 0)
        out += bytes(e)
    return out


HP = ('2DA V1.0\r\n0\r\n    SIDES   ROLLS   MODIFIER\r\n'
      + ''.join('%-4d1       1       5\r\n' % lv for lv in range(1, 51))).encode()


def main():
    od = sys.argv[1]
    files = {
        'IXFXB.EFF': eff(22, 2, 0, 0, 300),
        'IXFX182M.EFF': eff(182, 0, 0, 0, 300, b'IXNOITEM', b'IXFXB'),
        'IXFX182A.EFF': eff(182, 0, 0, 0, 300, b'AMUL01', b'IXFXB'),
        'IXSPLP.SPL': spl([(22, 1, 0, 0, 300)]),
        'HPWAR.2DA': HP,
        'WSPECIAL.2DA': (b'2DA V1.0\r\n0\r\n   HIT  DAMAGE  SPEED\r\n0   0     0       0\r\n1   0     0       -10\r\n'
                         b'2   1     2       -10\r\n3   3     3       -10\r\n4   3     4       -10\r\n5   3     5       -10\r\n'),
    }
    # SPLPROT: append the test row once (the copy's file comes from the test game, or the game's own via WeiDU)
    sp = next((os.path.join(od, n) for n in os.listdir(od) if n.lower() == 'splprot.2da'), None)
    if sp is None:
        sys.exit('splprot.2da is not in override: extract the game\'s own first (WeiDU --biff-get)')
    with open(sp, 'rb') as fh:
        lines = fh.read().decode('latin-1').splitlines()
    rows = [l for l in lines[3:] if l.strip()]
    index = next((i for i, l in enumerate(rows) if l.split()[0] == 'IXFXT'), None)
    if index is None:
        index = len(rows)
        with open(sp, 'ab') as fh:
            fh.write(b'IXFXT\t32\t5\t4\r\n')
    files['M_FXTROW.lua'] = ('FXT_SPLPROT_ROW = %d\n' % index).encode()
    for hp in ('HPWIZ', 'HPROGUE', 'HPPRS', 'HPMONK', 'HPBARB'):
        files[hp + '.2DA'] = HP
    for name, data in files.items():
        # resources in both cases for a case-sensitive file system (Linux); M_ files keep their name
        names = {name} if name.startswith('M_') else {name, name.lower()}
        for n in names:
            with open(os.path.join(od, n), 'wb') as fh:
                fh.write(data)
    print('wrote', ', '.join(files))


if __name__ == '__main__':
    main()
