"""Compare the direct callees of a Linux function and a candidate Windows function (manual verification).

Usage: python -I cmpcalls.py <lin_feat.pkl> <win_feat.pkl> <win symbols.json> <linuxVA> <winRVA> [<linuxVA> <winRVA>...]
Each Linux callee is mapped to its Windows RVA through the symbol table (name match by linux_addr, aliases
included); imports are compared by name. Prints both callee lists side by side (multiset), the mapped
overlap and the Linux callees with no Windows image. A high overlap with the remaining callees explained
by inlining is the evidence used in verified_*.json. No game data is stored by this tool.
"""
import collections
import json
import os
import pickle
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from binfeat import Binary  # noqa: F401,E402  (needed to unpickle)


def main():
    L = pickle.load(open(sys.argv[1], 'rb'))
    W = pickle.load(open(sys.argv[2], 'rb'))
    syms = json.load(open(sys.argv[3]))
    l2w = {}
    w2n = {}
    for s in syms:
        w = int(s['addr'], 16)
        w2n.setdefault(w, s['demangled'])
        if s.get('linux_addr'):
            l2w.setdefault(int(s['linux_addr'], 16), w)

    def lname(a):
        f = L.funcs.get(a)
        return f['name'] if f else hex(a)

    args = sys.argv[4:]
    for i in range(0, len(args), 2):
        la, wa = int(args[i], 16), int(args[i + 1], 16)
        fl, fw = L.feat.get(la), W.feat.get(wa)
        if fl is None or fw is None:
            print(f'== {la:#x} / {wa:#x}: no features ({"lin" if fl is None else "win"})')
            continue
        lc = collections.Counter()
        unm = collections.Counter()
        for k, t in fl['calls']:
            if k == 'i':
                lc['imp:' + str(t)] += 1
            elif t in l2w:
                lc[l2w[t]] += 1
            else:
                unm[lname(t)] += 1
        wc = collections.Counter()
        for k, t in fw['calls']:
            wc['imp:' + str(t) if k == 'i' else t] += 1
        both = lc & wc
        print(f'== lin {la:#x} {lname(la)}  <->  win {wa:#x}')
        print(f'   insns {fl["nins"]}/{fw["nins"]}  blocks {fl["nbb"]}/{fw["nbb"]}  '
              f'calls {sum(lc.values()) + sum(unm.values())}/{sum(wc.values())}  '
              f'mapped-common {sum(both.values())}/{sum(lc.values())}')
        for t, n in sorted(both.items(), key=lambda x: str(x[0])):
            print(f'   =  {n}x {t if isinstance(t, str) else hex(t)} {w2n.get(t, "") if not isinstance(t, str) else ""}')
        for t, n in sorted((lc - wc).items(), key=lambda x: str(x[0])):
            print(f'   L- {n}x {t if isinstance(t, str) else hex(t)} {w2n.get(t, "") if not isinstance(t, str) else ""}')
        for t, n in sorted((wc - lc).items(), key=lambda x: str(x[0])):
            print(f'   W+ {n}x {t if isinstance(t, str) else hex(t)} {w2n.get(t, "") if not isinstance(t, str) else ""}')
        for t, n in sorted(unm.items()):
            print(f'   L? {n}x {t} (no Windows match)')


if __name__ == '__main__':
    main()
