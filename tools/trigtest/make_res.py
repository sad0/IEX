"""Test resources for tools/trigtest (our own data, written into the test copy's override only).

Usage: python -I make_res.py <game dir> <weidu.exe>
  IXT13D.CRE  the test creature: the game's CAT.CRE with its own death variable IXT13D, script IXT13 (override slot,
              the other script slots cleared), neutral, 32000 HP
  IXT13.BCS   probe/IXT13.BAF compiled by WeiDU (Heard / AttackedBy with PartySlot1 and [ANYONE])
"""
import os
import shutil
import struct
import subprocess
import sys
import tempfile


def find(od, name):
    return next((os.path.join(od, n) for n in os.listdir(od) if n.lower() == name.lower()), None)


def main():
    game, weidu = sys.argv[1], sys.argv[2]
    od = os.path.join(game, 'override')
    src = find(od, 'CAT.CRE')
    if src is None:
        # vanilla game: the game's own file from its BIFFs (guarded WeiDU: no stdin, time limit)
        subprocess.run([weidu, '--game', game, '--use-lang', 'en_us', '--biff-get', 'cat.cre', '--out', od],
                       stdin=subprocess.DEVNULL, capture_output=True, cwd=game, timeout=120)
        src = find(od, 'CAT.CRE')
    if src is None:
        sys.exit('CAT.CRE is neither in override nor extractable')
    with open(src, 'rb') as fh:
        b = bytearray(fh.read())
    if b[0:8] != b'CRE V1.0':
        sys.exit('CAT.CRE is not CRE V1.0')
    struct.pack_into('<HH', b, 0x24, 32000, 32000)        # current / maximum HP
    for off in (0x248, 0x250, 0x258, 0x260, 0x268):      # override, class, race, general, default scripts
        b[off:off + 8] = bytes(8)
    b[0x248:0x248 + 5] = b'IXT13'
    b[0x270] = 128                                       # EA: NEUTRAL
    b[0x280:0x2a0] = bytes(32)
    b[0x280:0x280 + 6] = b'IXT13D'                       # death variable (script name)
    for n in ('IXT13D.CRE', 'ixt13d.cre'):  # both cases for a case-sensitive file system (Linux)
        with open(os.path.join(od, n), 'wb') as fh:
            fh.write(b)

    baf = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'probe', 'IXT13.BAF')
    tmp = tempfile.mkdtemp(prefix='trigtest')
    try:
        # guarded WeiDU: no stdin, time limit, output in a temporary folder
        r = subprocess.run([weidu, '--game', game, '--use-lang', 'en_us',
                            '--out', tmp, baf], stdin=subprocess.DEVNULL, capture_output=True, cwd=game,
                           text=True, timeout=120)
        out = find(tmp, 'IXT13.BCS')
        if out is None:
            sys.exit('WeiDU compile failed:\n' + r.stdout[-2000:] + r.stderr[-2000:])
        for n in ('IXT13.BCS', 'ixt13.bcs'):
            shutil.copy(out, os.path.join(od, n))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('wrote IXT13D.CRE, IXT13.BCS')


if __name__ == '__main__':
    main()
