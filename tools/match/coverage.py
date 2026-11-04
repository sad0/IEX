"""Coverage report of a match result. Usage: python -I coverage.py <lin_feat.pkl> <pairs.pkl>"""
import collections
import os
import pickle
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from binfeat import Binary  # noqa: F401

CLASSES = ['CGameSprite', 'CInfGame', 'CGameArea', 'CGameAIBase', 'CGameEffect', 'CBaldurChitin', 'CScreenWorld']


def group(name, dem):
    if re.match(r'^luaL?_', name):
        return name.split('_')[0] + '_*'
    m = re.match(r'^([A-Za-z_][\w]*)::', dem)
    return m.group(1) if m else ('C:' + name.split('_')[0] if '_' in name else 'C:other')


def main():
    L = pickle.load(open(sys.argv[1], 'rb'))
    m = pickle.load(open(sys.argv[2], 'rb'))
    tot, hit = collections.Counter(), collections.Counter()
    conf = collections.defaultdict(collections.Counter)
    for a, f in L.funcs.items():
        if f.get('static'):
            continue
        g = group(f['name'], f['dem'])
        tot[g] += 1
        if a in m:
            hit[g] += 1
            conf[g][m[a][1]] += 1
    nt = sum(tot.values())
    nh = sum(hit.values())
    print(f'named linux functions matched: {nh}/{nt} = {100 * nh / nt:.1f}%')
    for g in CLASSES + ['lua_*', 'luaL_*']:
        print(f'  {g:16s} {hit[g]:5d}/{tot[g]:5d}  {dict(conf[g])}')
    print('largest groups:')
    for g, n in tot.most_common(int(sys.argv[3]) if len(sys.argv) > 3 else 25):
        print(f'  {g:30s} {hit[g]:5d}/{n:5d}')


if __name__ == '__main__':
    main()
