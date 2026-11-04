"""Print side-by-side features of matched pairs. Usage: python -I inspect_pair.py <lin.pkl> <win.pkl> <pairs.pkl> <linux name|0xaddr>..."""
import os
import pickle
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from binfeat import Binary  # noqa: F401


def main():
    L = pickle.load(open(sys.argv[1], 'rb'))
    W = pickle.load(open(sys.argv[2], 'rb'))
    m = pickle.load(open(sys.argv[3], 'rb'))
    inv = {}
    for l, (w, c, mt) in m.items():
        inv.setdefault(w, []).append(l)
    byn = {f['name']: a for a, f in L.funcs.items()}

    def ln(a):
        return L.funcs[a]['name'] if a in L.funcs else hex(a)

    def wn(a):
        return '+'.join(L.funcs[x]['name'] for x in inv[a]) if a in inv else f'w:{a:x}'
    for q in sys.argv[4:]:
        l = int(q, 16) if q.startswith('0x') else byn[q]
        fl = L.feat[l]
        print(f'== {ln(l)} lin {l:#x} nins {fl["nins"]} nbb {fl["nbb"]}')
        print('  L calls:', [x[1] if x[0] == 'i' else ln(x[1]) for x in fl['calls']])
        print('  L strs :', fl['strs'][:8])
        if l in m:
            w, c, mt = m[l]
            fw = W.feat[w]
            print(f'  -> win {w:#x} {c} {mt}  nins {fw["nins"]} nbb {fw["nbb"]}')
            print('  W calls:', [x[1] if x[0] == 'i' else wn(x[1]) for x in fw['calls']])
            print('  W strs :', fw['strs'][:8])


if __name__ == '__main__':
    main()
