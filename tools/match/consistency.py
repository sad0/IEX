"""Call-graph consistency of a match: for each pair with >=2 matched callees (or callers), the fraction that
map onto the Windows function's callees (callers). Wrong matches show low agreement.
Usage: python -I consistency.py <lin.pkl> <win.pkl> <pairs.pkl> [--bad N]"""
import collections
import os
import pickle
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from binfeat import Binary  # noqa: F401


def agreement(L, W, m):
    wthunk = {a: f['thunk'] for a, f in W.funcs.items() if f.get('thunk')}
    lcallers, wcallers = collections.defaultdict(set), collections.defaultdict(set)
    for a, f in L.feat.items():
        for k, t in f['calls']:
            if k == 'f':
                lcallers[t].add(a)
    for a, f in W.feat.items():
        for k, t in f['calls']:
            if k == 'f':
                wcallers[wthunk.get(t, t)].add(a)
    out = {}
    for l, (w, c, mt) in m.items():
        lc = {m[t][0] for k, t in L.feat[l]['calls'] if k == 'f' and t in m}
        wc = {wthunk.get(t, t) for k, t in W.feat[w]['calls'] if k == 'f'}
        lr = {m[t][0] for t in lcallers[l] if t in m}
        wr = wcallers[w]
        n = len(lc) + len(lr)
        if n < 2:
            continue
        out[l] = ((len(lc & wc) + len(lr & wr)) / n, n)
    return out


def main():
    L = pickle.load(open(sys.argv[1], 'rb'))
    W = pickle.load(open(sys.argv[2], 'rb'))
    m = pickle.load(open(sys.argv[3], 'rb'))
    ag = agreement(L, W, m)
    by = collections.defaultdict(list)
    for l, (a, n) in ag.items():
        c, mt = m[l][1], m[l][2].split(' ')[0]
        by[c].append(a)
        by[c + ':' + mt].append(a)
    for k in sorted(by):
        v = by[k]
        print(f'{k:40s} n={len(v):5d} mean={sum(v) / len(v):.2f} bad(<0.34)={sum(x < 0.34 for x in v) / len(v):.1%}')
    if '--bad' in sys.argv:
        nb = int(sys.argv[sys.argv.index('--bad') + 1])
        bad = sorted((a, -n, l) for l, (a, n) in ag.items())[:nb]
        for a, n, l in bad:
            print(f'  {a:.2f} n={-n} {L.funcs[l]["name"]} -> {m[l][0]:#x} {m[l][1]} {m[l][2]}')


if __name__ == '__main__':
    main()
