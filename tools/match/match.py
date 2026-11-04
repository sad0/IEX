"""Name Windows (PE, stripped) functions from a symbolized Linux (ELF) build of the same game version.

Clean-room: uses only the two game binaries (+ the Ghidra function list of the PE).

Usage: python -I match.py <lin_feat.pkl> <win_feat.pkl> <out.json> [--report report.txt]

Phases (see docs/MATCHING_METHOD.md):
  1 unique string literals          4 callee-sequence alignment (iterated)
  2 RTTI vtables vs _ZTV slot-by-slot 5 unique caller sets / function-pointer refs
  3 (string ptr, function ptr) tables 6 rarer-string set similarity
"""
import collections
import difflib
import json
import math
import pickle
import re
import struct
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from binfeat import Binary  # noqa: E402,F401  (needed for unpickling)

CONF_RANK = {'high': 3, 'medium': 2, 'low': 1}


class Matcher:
    def __init__(self, L, W):
        self.L, self.W = L, W
        self.m = {}        # lin -> (win, conf, method)
        self.inv = collections.defaultdict(set)  # win -> {lin}
        self.lcallers = self._callers(L)
        self.wcallers = self._callers(W)
        wimp = {n for f in W.feat.values() for k, n in f['calls'] if k == 'i'}
        limp = {n for f in L.feat.values() for k, n in f['calls'] if k == 'i'}
        self.common_imp = wimp & limp
        # Windows thunks (jmp to function): resolve to target for call sequences
        self.wthunk = {a: f['thunk'] for a, f in W.funcs.items() if f.get('thunk')}
        self.impmap, self.impinv = {}, {}   # linux import name <-> windows static CRT function

    @staticmethod
    def _callers(B):
        c = collections.defaultdict(set)
        for a, f in B.feat.items():
            for k, t in f['calls']:
                if k == 'f':
                    c[t].add(a)
        return c

    # ------------------------------------------------------------ core helpers
    def add(self, l, w, conf, method):
        if l in self.m:
            return False
        self.m[l] = (w, conf, method)
        self.inv[w].add(l)
        return True

    def wfree(self, w):
        return w not in self.inv

    def sim(self, l, w):
        """0..1 structural similarity, tolerant to GCC/MSVC differences."""
        a, b = self.L.feat[l], self.W.feat[w]
        s = []

        def ratio(x, y, k=4):
            return (min(x, y) + k) / (max(x, y) + k)
        s.append(ratio(a['nins'], b['nins'], 8) ** 0.5)
        s.append(ratio(a['nbb'], b['nbb'], 3) ** 0.5)
        s.append(ratio(len(a['calls']), len(b['calls']), 2) ** 0.5)
        sa, sb = set(a['strs']), set(b['strs'])
        if sa or sb:
            s.append(len(sa & sb) / len(sa | sb))
        fa, fb = set(a['flts']), set(b['flts'])
        if fa or fb:
            s.append(len(fa & fb) / len(fa | fb))
        ia, ib = set(a['imms']), set(b['imms'])
        if len(ia | ib) >= 2:
            s.append(len(ia & ib) / len(ia | ib))
        return sum(s) / len(s)

    # ------------------------------------------------------------ phase 0 exports
    def phase_exports(self):
        lby = collections.defaultdict(list)
        for a, f in self.L.funcs.items():
            lby[f['name']].append(a)
        n = 0
        for w, names in getattr(self.W, 'exports', {}).items():
            for nm in names:
                for l in lby.get(nm, []):
                    n += self.add(l, w, 'high', 'pe-export')
        return n

    # ------------------------------------------------------------ phase 1 strings
    def phase_strings(self):
        Ls, Ws = collections.defaultdict(set), collections.defaultdict(set)
        for a, f in self.L.feat.items():
            for s in f['strs']:
                Ls[s].add(a)
        for a, f in self.W.feat.items():
            for s in f['strs']:
                Ws[s].add(a)
        self.Ls, self.Ws = Ls, Ws
        votes = collections.Counter()
        ltot, wtot = collections.Counter(), collections.Counter()
        for s, ls in Ls.items():
            ws = Ws.get(s)
            if ws and len(ls) == 1 and len(ws) == 1:
                l, = ls
                w, = ws
                votes[(l, w)] += 1
                ltot[l] += 1
                wtot[w] += 1
        best_l, best_w = {}, {}
        for (l, w), v in votes.items():
            if v > best_l.get(l, (0, None))[0]:
                best_l[l] = (v, w)
            if v > best_w.get(w, (0, None))[0]:
                best_w[w] = (v, l)
        n = 0
        for l, (v, w) in best_l.items():
            if best_w[w][1] != l or l in self.m or not self.wfree(w):
                continue
            if v / ltot[l] < 0.5 or v / wtot[w] < 0.5:
                continue
            sm = self.sim(l, w)
            if v >= 2 and sm >= 0.45:
                conf = 'high'
            elif v >= 1 and sm >= 0.55:
                conf = 'high' if sm >= 0.7 else 'medium'
            elif sm >= 0.4:
                conf = 'medium'
            else:
                conf = 'low'
            n += self.add(l, w, conf, f'unique-string x{v}')
        return n

    def phase_rare_strings(self):
        """Unmatched functions sharing rarer strings (idf-weighted Jaccard), mutual best."""
        idf = {}
        for s in set(self.Ls) & set(self.Ws):
            k = max(len(self.Ls[s]), len(self.Ws[s]))
            if k <= 12:
                idf[s] = 1.0 / k
        cand = collections.defaultdict(float)
        for s, wgt in idf.items():
            for l in self.Ls[s]:
                if l in self.m:
                    continue
                for w in self.Ws[s]:
                    if self.wfree(w):
                        cand[(l, w)] += wgt
        best_l, best_w = {}, {}
        for (l, w), v in cand.items():
            la = set(self.L.feat[l]['strs'])
            wa = set(self.W.feat[w]['strs'])
            tot = sum(idf.get(s, 0) for s in la | wa)
            sc = v / tot if tot else 0
            if sc > best_l.get(l, (0, None, 0))[0]:
                best_l[l] = (sc, w, best_l.get(l, (0, None, 0))[0])
            elif sc > best_l[l][2]:
                best_l[l] = (best_l[l][0], best_l[l][1], sc)
            if sc > best_w.get(w, (0, None, 0))[0]:
                best_w[w] = (sc, l, best_w.get(w, (0, None, 0))[0])
            elif sc > best_w[w][2]:
                best_w[w] = (best_w[w][0], best_w[w][1], sc)
        n = 0
        for l, (sc, w, second) in best_l.items():
            if best_w[w][1] != l or sc < 0.5 or second >= sc * 0.8 or best_w[w][2] >= sc * 0.8:
                continue
            sm = self.sim(l, w)
            if sm < 0.45:
                continue
            n += self.add(l, w, 'medium' if sc >= 0.7 and sm >= 0.6 else 'low', f'string-set {sc:.2f}')
        return n

    # ------------------------------------------------------------ phase 2 vtables
    def lin_vtables(self):
        L = self.L
        out = {}
        for a, (name, size, dem) in L.objects.items():
            if not name.startswith('_ZTV'):
                continue
            cls = dem[len('vtable for '):] if dem.startswith('vtable for ') else None
            if not cls:
                continue
            slots = []
            p = a + 16
            while p < a + size:
                if p in L.imports:
                    slots.append(('i', L.imports[p]))
                elif p in L.ptrs and L.ptrs[p] in L.funcs:
                    slots.append(('f', L.ptrs[p]))
                else:
                    break
                p += 8
            out[cls] = slots
        return out

    def win_vtables(self):
        """Parse MSVC RTTI ourselves: complete object locator -> type descriptor name -> vtable."""
        W = self.W
        rdata = [s for s in W.segs if s[3] in ('.rdata', '.data')]
        out = {}
        for va, ptr in W.ptrs.items():
            seg = W.seg_of(va)
            if not seg or seg[3] != '.rdata':
                continue
            col = ptr
            hdr = W.read(col, 24)
            if not hdr or len(hdr) < 24:
                continue
            sig, off, cdo, td, chd,self_ = struct.unpack('<IIIIII', hdr)
            if sig != 1 or self_ != col or off != 0:
                continue
            tname = W.cstr(td + 16)
            if not tname or not tname.startswith('.?AV') and not tname.startswith('.?AU'):
                continue
            cls = demangle_msvc_type(tname[4:])
            if not cls:
                continue
            slots = []
            p = va + 8
            while True:
                t = W.ptrs.get(p)
                if t is None or t not in W.funcs:
                    break
                slots.append(('f', t))
                p += 8
            if cls in out and len(out[cls]) >= len(slots):
                continue
            out[cls] = slots
        return out

    def phase_vtables(self):
        lv, wv = self.lin_vtables(), self.win_vtables()
        self.lv, self.wv = lv, wv
        L = self.L
        wslot_use = collections.Counter(t for s in wv.values() for k, t in s)
        stats = collections.Counter()
        pairs = collections.defaultdict(list)  # (l,w) -> [(cls, ok)]
        for cls, ls in lv.items():
            ws = wv.get(cls)
            if ws is None:
                stats['no-win-vtable'] += 1
                continue
            # drop the Itanium complete-object destructor (D1); keep D0 (deleting) <-> scalar deleting dtor
            adj = []
            for k, t in ls:
                if k == 'f' and re.search(r'D1Ev$', L.funcs[t]['name']):
                    continue
                adj.append((k, t))
            exact = len(adj) == len(ws)
            stats['exact' if exact else 'len-mismatch'] += 1
            n = len(adj) if exact else 0
            if not exact:
                # align the common prefix only while slot kinds look consistent
                n = min(len(adj), len(ws))
            for i in range(n):
                (k, l), (_, w) = adj[i], ws[i]
                if k != 'f':
                    continue
                pairs[(l, w)].append((cls, exact, i))
        # consolidate: a lin function may sit in many vtables (inherited) -> should always map to same w
        byl = collections.defaultdict(collections.Counter)
        for (l, w), lst in pairs.items():
            byl[l][w] += sum(2 if ex else 1 for _, ex, _ in lst)
        n = 0
        for l, cnt in byl.items():
            (w, v), = cnt.most_common(1)
            tot = sum(cnt.values())
            if v / tot < 0.75:
                continue
            exact = any(ex for c, ex, _ in pairs[(l, w)])
            sm = self.sim(l, w)
            name = L.funcs[l]['name']
            if exact and (sm >= 0.5 or self.L.feat[l]['nins'] <= 6):
                conf = 'high'
            elif exact or sm >= 0.6:
                conf = 'medium'
            else:
                conf = 'low'
            if L.funcs[l]['name'] in ('__cxa_pure_virtual',):
                continue
            n += self.add(l, w, conf, 'vtable' + ('' if exact else '-prefix'))
        return n, stats

    # ------------------------------------------------------------ phase 2b vtables via ctor/dtor refs
    def _vt_init(self):
        L, W = self.L, self.W
        self.lvt = {}  # vtable start va -> class name
        for a, (name, size, dem) in L.objects.items():
            if name.startswith('_ZTV'):
                cls = dem[len('vtable for '):] if dem.startswith('vtable for ') else name
                for p in range(a + 16, a + size, 8):
                    self.lvt[p] = cls
        self.wref = set()
        for f in W.feat.values():
            self.wref.update(f['drefs'])
        self.lrefcnt = collections.Counter(t for f in L.feat.values() for t in f['drefs'])
        self.vt_done = set()
        self.vt_pairs = {}

    def _is_dtor1(self, l):
        f = self.L.funcs[l]
        return any(re.search(r'D[12]Ev$', n) for n in [f['name']] + f.get('aliases', []))

    def lin_slots(self, p):
        L, out = self.L, []
        while True:
            if p in L.imports:
                out.append(('i', L.imports[p]))
            elif p in L.ptrs and L.ptrs[p] in L.funcs:
                out.append(('f', L.ptrs[p]))
            else:
                break
            p += 8
            if p in self.lrefcnt:   # another vtable start referenced by code
                break
        return out

    def win_slots(self, p, maxn):
        W, out = self.W, []
        while len(out) < maxn + 8:
            t = W.ptrs.get(p)
            if t is None or t not in W.funcs:
                break
            out.append(('f', t))
            p += 8
            if p in self.wref:
                break
        return out

    def phase_vtable_refs(self):
        if not hasattr(self, 'lvt'):
            self._vt_init()
        W = self.W
        votes = collections.Counter()
        for l, (w, conf, meth) in list(self.m.items()):
            if conf == 'low':
                continue
            a = list(dict.fromkeys(t for t in self.L.feat[l]['drefs'] if t in self.lvt and self.lin_slots(t)))
            if not a:
                continue
            b = list(dict.fromkeys(t for t in self.W.feat[w]['drefs']
                                   if W.ptrs.get(t) in W.funcs and W.ptrs.get(t + 8) in W.funcs
                                   and (W.seg_of(t) or (0, 0, 0, ''))[3] == '.rdata'))
            if len(a) == len(b):
                for x, y in zip(a, b):
                    votes[(x, y)] += 1
        # pair vtables by content: positional agreement of already matched slots
        if not hasattr(self, 'wvt_index'):
            self.wvt_starts = [t for t in self.wref if W.ptrs.get(t) in W.funcs and W.ptrs.get(t + 8) in W.funcs
                               and (W.seg_of(t) or (0, 0, 0, ''))[3] == '.rdata']
            self.wvt_slots = {t: self.win_slots(t, 400) for t in self.wvt_starts}
            self.wvt_index = collections.defaultdict(set)
            for t, sl in self.wvt_slots.items():
                for i, (_, f) in enumerate(sl):
                    self.wvt_index[(i, f)].add(t)
        lstarts = {}
        for a, (name, size, dem) in self.L.objects.items():
            if name.startswith('_ZTV') and a + 16 not in self.vt_done:
                lstarts[a + 16] = None
        for x in lstarts:
            ls = [s for s in self.lin_slots(x) if not (s[0] == 'f' and self._is_dtor1(s[1]))]
            if len(ls) < 2:
                continue
            sc = collections.Counter()
            for i, (k, l) in enumerate(ls):
                if k == 'f' and l in self.m and self.m[l][1] != 'low':
                    for t in self.wvt_index.get((i, self.m[l][0]), ()):
                        sc[t] += 1
            if not sc:
                continue
            top = sc.most_common(3)
            best, v = top[0]
            # prefer the candidate whose length matches; require clear win
            cands = [t for t, c in top if c == v]
            if len(cands) > 1:
                cands = [t for t in cands if len(self.wvt_slots[t]) == len(ls)]
            if len(cands) != 1 or v < 2:
                continue
            nmatched = sum(1 for k, l in ls if k == 'f' and l in self.m)
            if v < 0.6 * nmatched:
                continue
            votes[(x, cands[0])] += 2
        # resolve vtable pairs (mutual best)
        bl, bw = {}, {}
        for (x, y), v in votes.items():
            if v > bl.get(x, (0, None))[0]:
                bl[x] = (v, y)
            if v > bw.get(y, (0, None))[0]:
                bw[y] = (v, x)
        n = 0
        slotvotes = collections.defaultdict(collections.Counter)
        for x, (v, y) in bl.items():
            if bw[y][1] != x or x in self.vt_done:
                continue
            self.vt_done.add(x)
            ls = [s for s in self.lin_slots(x) if not (s[0] == 'f' and self._is_dtor1(s[1]))]
            ws = self.win_slots(y, len(ls))
            exact = len(ls) == len(ws)
            self.vt_pairs[x] = (y, self.lvt[x], len(ls), len(ws))
            for (k, l), (_, w) in zip(ls, ws):
                if k == 'f':
                    slotvotes[l][(w, exact)] += 1
        for l, cnt in slotvotes.items():
            if l in self.m:
                continue
            ws = collections.Counter()
            for (w, ex), c in cnt.items():
                ws[w] += c
            (w, c), = ws.most_common(1)
            if c / sum(ws.values()) < 0.75:
                continue
            exact = cnt.get((w, True), 0) > 0
            sm = self.sim(l, w)
            small = self.L.feat[l]['nins'] <= 8
            if exact and (sm >= 0.55 or small):
                conf = 'high' if not small or sm >= 0.6 else 'medium'
            elif sm >= 0.6:
                conf = 'medium'
            else:
                conf = 'low'
            n += self.add(l, w, conf, 'vtable-slot' + ('' if exact else '-prefix'))
        return n

    # ------------------------------------------------------------ phase 3 tables
    def ptr_tables(self, B):
        """(string ptr, function ptr) pairs in data: luaL_Reg-like tables. key -> func."""
        recs = {}
        for va, t in B.ptrs.items():
            if t not in B.funcs:
                continue
            sp = B.ptrs.get(va - 8)
            if sp is None:
                continue
            s = B.cstr(sp)
            if s is None:
                continue
            recs[va] = (s, t)
        out = collections.defaultdict(set)
        for va, (s, t) in recs.items():
            prev = recs.get(va - 16, ('', 0))[0]
            nxt = recs.get(va + 16, ('', 0))[0]
            out[(s, prev, nxt)].add(t)
            out[(s,)].add(t)
        return out

    @staticmethod
    def ref_names(B):
        """Function pointers taken next to a string literal in code (lua_register / pushcclosure+setglobal
        patterns): key (string after, string before) -> {function}."""
        out = collections.defaultdict(set)
        for a, f in B.feat.items():
            sq = f['seq']
            for i, (k, v) in enumerate(sq):
                if k != 'r':
                    continue
                nxt = next((x for kk, x in sq[i + 1:i + 3] if kk == 's'), None)
                prv = next((x for kk, x in reversed(sq[max(0, i - 2):i]) if kk == 's'), None)
                if nxt is None and prv is None:
                    continue
                out[('n', nxt)].add(v)
                out[('p', prv)].add(v)
                out[('np', nxt, prv)].add(v)
        return out

    def phase_ref_names(self):
        lt, wt = self.ref_names(self.L), self.ref_names(self.W)
        votes = collections.Counter()
        for key in set(lt) & set(wt):
            if any(x is None for x in key[1:]):
                continue
            ls, ws = lt[key], wt[key]
            if len(ls) == 1 and len(ws) == 1:
                votes[(next(iter(ls)), next(iter(ws)))] += 1
        return self._accept_votes(votes, 'string-adjacent-fnptr', min_sim=0.0)

    def phase_tables(self):
        lt, wt = self.ptr_tables(self.L), self.ptr_tables(self.W)
        n = 0
        for key in sorted(set(lt) & set(wt), key=len, reverse=True):
            ls, ws = lt[key], wt[key]
            if len(ls) != 1 or len(ws) != 1:
                continue
            l, = ls
            w, = ws
            if l in self.m or not self.wfree(w):
                continue
            n += self.add(l, w, 'high' if len(key) == 3 or self.sim(l, w) >= 0.5 else 'medium', 'name-table')
        return n

    # ------------------------------------------------------------ phase 4 calls
    def _ltok(self, k, t):
        if k == 'i':
            if t in self.common_imp or t in self.impmap:
                return ('i', t)
            return ('j', t)  # linux import whose windows counterpart is (yet) unknown static CRT code
        if t in self.m:
            return ('m', self.m[t][0])
        return ('u', t)

    def _wtok(self, k, t):
        if k == 'i':
            return ('i', t) if t in self.common_imp else None
        t = self.wthunk.get(t, t)
        if t not in self.W.feat:
            return None
        if t in self.impinv:
            return ('i', self.impinv[t])
        if t in self.inv:
            return ('m', t)
        return ('u', t)

    def phase_calls(self, field='calls', label='callee-align'):
        votes = collections.Counter()
        ivotes = collections.Counter()
        for l, (w, conf, meth) in list(self.m.items()):
            if conf == 'low' or len(self.inv[w]) > 1:
                continue
            a = [x for x in (self._ltok(*c) for c in self.L.feat[l][field]) if x]
            b = [x for x in (self._wtok(*c) for c in self.W.feat[w][field]) if x]
            if not any(x[0] in 'uj' for x in a) or not any(x[0] == 'u' for x in b):
                continue
            ka = [x if x[0] not in 'uj' else ('u',) for x in a]
            kb = [x if x[0] != 'u' else ('u',) for x in b]
            sm = difflib.SequenceMatcher(None, ka, kb, autojunk=False)
            for tag, i1, i2, j1, j2 in sm.get_opcodes():
                if tag == 'equal' or (tag == 'replace' and i2 - i1 == j2 - j1):
                    wgt = 1 if tag == 'equal' else 0.5
                    for i, j in zip(range(i1, i2), range(j1, j2)):
                        if a[i][0] == 'u' and b[j][0] == 'u':
                            votes[(a[i][1], b[j][1])] += wgt
                        elif a[i][0] == 'j' and b[j][0] == 'u':
                            ivotes[(a[i][1], b[j][1])] += wgt
        self._accept_imports(ivotes)
        return self._accept_votes(votes, label)

    def _accept_imports(self, ivotes):
        bl, bw, lt, wt = {}, {}, collections.Counter(), collections.Counter()
        for (x, y), v in ivotes.items():
            if x in self.impmap or y in self.impinv or y in self.inv:
                continue
            lt[x] += v
            wt[y] += v
            if v > bl.get(x, (0, None))[0]:
                bl[x] = (v, y)
            if v > bw.get(y, (0, None))[0]:
                bw[y] = (v, x)
        for x, (v, y) in bl.items():
            if bw[y][1] == x and v >= 3 and v / lt[x] >= 0.6 and v / wt[y] >= 0.6:
                self.impmap[x] = y
                self.impinv[y] = x

    def phase_callee_sets(self):
        """Order-free: unmatched distinct callees of a matched pair, paired by call count when unambiguous
        (MSVC and GCC lay out basic blocks differently, so call order is only a hint)."""
        votes = collections.Counter()
        for l, (w, conf, meth) in list(self.m.items()):
            if conf == 'low' or len(self.inv[w]) > 1:
                continue
            ca = collections.Counter(t for k, t in self.L.feat[l]['calls'] if k == 'f' and t not in self.m)
            cb = collections.Counter()
            for k, t in self.W.feat[w]['calls']:
                if k == 'f':
                    t = self.wthunk.get(t, t)
                    if t in self.W.feat and self.wfree(t):
                        cb[t] += 1
            if not ca or not cb:
                continue
            if len(ca) == 1 and len(cb) == 1:
                votes[(next(iter(ca)), next(iter(cb)))] += 1
                continue
            byc_a, byc_b = collections.defaultdict(list), collections.defaultdict(list)
            for t, c in ca.items():
                byc_a[c].append(t)
            for t, c in cb.items():
                byc_b[c].append(t)
            for c, la in byc_a.items():
                lb = [t for t in byc_b.get(c, []) if t not in self.impinv]
                if len(la) == 1 and len(lb) == 1:
                    votes[(la[0], lb[0])] += 0.5 if c == 1 else 1
                elif 1 < len(la) == len(lb) <= 6:
                    for x in la:
                        sc = sorted(((self.sim(x, y), y) for y in lb), reverse=True)
                        if sc[0][0] >= 0.75 and sc[1][0] < sc[0][0] - 0.15:
                            votes[(x, sc[0][1])] += 0.5
        return self._accept_votes(votes, 'callee-set', min_sim=0.6)

    def _accept_votes(self, votes, label, min_sim=0.5, floor=None):
        lt, wt = collections.Counter(), collections.Counter()
        best_l, best_w = {}, {}
        for (l, w), v in votes.items():
            if l in self.m or not self.wfree(w):
                continue
            lt[l] += v
            wt[w] += v
            if v > best_l.get(l, (0, None))[0]:
                best_l[l] = (v, w)
            if v > best_w.get(w, (0, None))[0]:
                best_w[w] = (v, l)
        n = 0
        for l, (v, w) in best_l.items():
            if best_w[w][1] != l:
                continue
            pl, pw = v / lt[l], v / wt[w]
            if pl < 0.6 or pw < 0.6:
                continue
            sm = self.sim(l, w)
            if sm < min_sim and not (v >= 3 and sm >= min_sim - 0.15):
                continue
            if v >= 2 and sm >= 0.65 and pl >= 0.8 and pw >= 0.8:
                conf = 'high'
            elif v >= 1 and sm >= 0.6:
                conf = 'medium'
            else:
                conf = 'low'
            if floor and CONF_RANK[conf] < CONF_RANK[floor] and sm >= 0.6:
                conf = floor
            n += self.add(l, w, conf, f'{label} x{v:g}')
        return n

    def phase_common_callee(self):
        """Unmatched l with >=2 matched callers: the unmatched Windows functions called by all their images."""
        wcallees = {}

        def wc(w):
            if w not in wcallees:
                s = set()
                for k, t in self.W.feat[w]['calls']:
                    if k == 'f':
                        t = self.wthunk.get(t, t)
                        if t in self.W.feat and self.wfree(t):
                            s.add(t)
                wcallees[w] = s
            return wcallees[w]
        votes = collections.Counter()
        for l in self.L.feat:
            if l in self.m:
                continue
            cs = [self.m[c][0] for c in self.lcallers.get(l, ()) if c in self.m and self.m[c][1] != 'low'
                  and len(self.inv[self.m[c][0]]) == 1]
            cs = list(set(cs))
            if len(cs) < 2:
                continue
            s = None
            for w in cs:
                s = wc(w) if s is None else s & wc(w)
                if not s:
                    break
            if not s:
                continue
            if len(s) == 1:
                votes[(l, next(iter(s)))] += 1
            elif len(s) <= 4:
                sc = sorted(((self.sim(l, y), y) for y in s), reverse=True)
                if sc[0][0] >= 0.75 and sc[1][0] < sc[0][0] - 0.15:
                    votes[(l, sc[0][1])] += 0.5
        return self._accept_votes(votes, 'common-callee', min_sim=0.55, floor='medium')

    def phase_callers(self):
        """Unmatched functions whose callers are all matched: unique matched-caller set on both sides."""
        def key_l(l):
            cs = self.lcallers.get(l)
            if not cs or any(c not in self.m for c in cs):
                return None
            return frozenset(self.m[c][0] for c in cs)

        def key_w(w):
            cs = self.wcallers.get(w)
            if not cs:
                return None
            cs = {self.wthunk.get(c, c) for c in cs}
            if any(c not in self.inv for c in cs):
                return None
            return frozenset(cs)
        lk = collections.defaultdict(list)
        for l in self.L.feat:
            if l not in self.m:
                k = key_l(l)
                if k:
                    lk[k].append(l)
        wk = collections.defaultdict(list)
        for w in self.W.feat:
            if self.wfree(w):
                k = key_w(w)
                if k:
                    wk[k].append(w)
        votes = collections.Counter()
        for k, ls in lk.items():
            ws = wk.get(k)
            if not ws:
                continue
            if len(ls) == 1 and len(ws) == 1:
                votes[(ls[0], ws[0])] += 1
            elif len(ls) <= 4 and len(ls) == len(ws):
                # pick by similarity, only if clear
                for l in ls:
                    sc = sorted(((self.sim(l, w), w) for w in ws), reverse=True)
                    if sc[0][0] >= 0.7 and (len(sc) == 1 or sc[1][0] < sc[0][0] - 0.15):
                        votes[(l, sc[0][1])] += 1
        return self._accept_votes(votes, 'caller-set', min_sim=0.6)

    # ------------------------------------------------------------ globals
    def phase_globals(self):
        if not hasattr(self, 'gm'):
            self.gm, self.gminv = {}, {}
        votes = collections.Counter()
        for l, (w, conf, meth) in list(self.m.items()):
            if conf == 'low' or len(self.inv[w]) > 1:
                continue
            a = [('g', self.gm[t]) if t in self.gm else ('u', t) for t in self.L.feat[l]['drefs'] if t not in self.lvt]
            b = [('g', t) if t in self.gminv else ('u', t) for t in self.W.feat[w]['drefs']]
            if not a or not b:
                continue
            ka = [x if x[0] != 'u' else ('u',) for x in a]
            kb = [x if x[0] != 'u' else ('u',) for x in b]
            for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, ka, kb, autojunk=False).get_opcodes():
                if tag == 'equal' or (tag == 'replace' and i2 - i1 == j2 - j1):
                    for i, j in zip(range(i1, i2), range(j1, j2)):
                        if a[i][0] == 'u' and b[j][0] == 'u':
                            votes[(a[i][1], b[j][1])] += 1 if tag == 'equal' else 0.5
        bl, bw, lt, wt = {}, {}, collections.Counter(), collections.Counter()
        for (x, y), v in votes.items():
            lt[x] += v
            wt[y] += v
            if v > bl.get(x, (0, None))[0]:
                bl[x] = (v, y)
            if v > bw.get(y, (0, None))[0]:
                bw[y] = (v, x)
        ng = 0
        for x, (v, y) in bl.items():
            if bw[y][1] == x and v >= 1 and v / lt[x] >= 0.6 and v / wt[y] >= 0.6 and y not in self.gminv:
                self.gm[x] = y
                self.gminv[y] = x
                ng += 1
        # functions sharing a mapped global that only they reference (among unmatched)
        lr, wr = collections.defaultdict(set), collections.defaultdict(set)
        for a, f in self.L.feat.items():
            for t in f['drefs']:
                if t in self.gm:
                    lr[t].add(a)
        for a, f in self.W.feat.items():
            for t in f['drefs']:
                if t in self.gminv:
                    wr[t].add(a)
        fv = collections.Counter()
        for x, y in self.gm.items():
            ls = {l for l in lr[x] if l not in self.m}
            ws = {w for w in wr[y] if self.wfree(w)}
            if len(ls) == 1 and len(ws) == 1 and len(lr[x]) <= 4:
                fv[(next(iter(ls)), next(iter(ws)))] += 1
        return ng, self._accept_votes(fv, 'unique-global', min_sim=0.55)

    # ------------------------------------------------------------ layout (source order inside a TU)
    def phase_layout(self, maxgap=6):
        """Both compilers emit a translation unit's functions in source order. Between two consecutive
        anchors that are consecutive in both binaries, equal-size gaps of unmatched functions pair in order."""
        anchors = sorted((l, w) for l, (w, c, mt) in self.m.items() if c != 'low' and len(self.inv[w]) == 1)
        lsorted = sorted(self.L.feat)
        wsorted = sorted(self.W.feat)
        import bisect
        n = 0
        for (l1, w1), (l2, w2) in zip(anchors, anchors[1:]):
            if not (w1 < w2) or l2 - l1 > 0x4000 or w2 - w1 > 0x4000:
                continue
            i1, i2 = bisect.bisect_right(lsorted, l1), bisect.bisect_left(lsorted, l2)
            j1, j2 = bisect.bisect_right(wsorted, w1), bisect.bisect_left(wsorted, w2)
            gl, gw = lsorted[i1:i2], wsorted[j1:j2]
            if not gl or len(gl) != len(gw) or len(gl) > maxgap:
                continue
            if any(x in self.m for x in gl) or any(not self.wfree(x) for x in gw):
                continue
            sims = [self.sim(a, b) for a, b in zip(gl, gw)]
            if min(sims) < 0.45:
                continue
            for a, b, s in zip(gl, gw, sims):
                n += self.add(a, b, 'medium' if s >= 0.65 and len(gl) <= 3 else 'low', f'layout-gap {len(gl)}')
        return n

    # ------------------------------------------------------------ run
    def run(self, log, ov=None):
        log(f'phase exports: +{self.phase_exports()}')
        if ov:
            apply_overrides(self, ov, log)
        log(f'phase strings: +{self.phase_strings()}')
        n, st = self.phase_vtables()
        log(f'phase vtables: +{n}  {dict(st)}  (lin {len(self.lv)}, win {len(self.wv)} classes)')
        log(f'phase tables: +{self.phase_tables()}')
        log(f'phase string-adjacent fnptrs: +{self.phase_ref_names()}')
        for it in range(30):
            a = self.phase_calls() + self.phase_callee_sets()
            b = self.phase_calls('frefs', 'fref-align')
            c = self.phase_callers() + self.phase_common_callee()
            d = self.phase_rare_strings() if it % 3 == 0 else 0
            e = self.phase_vtable_refs()
            g, f = self.phase_globals()
            if a + b + c + d + e + f + g == 0:
                f += self.phase_layout()
            log(f'iter {it}: callee +{a} fref +{b} callers +{c} rare-str +{d} vtable +{e} globals {len(self.gm)} (+{g}) '
                f'glob-fn +{f}  total {len(self.m)}')
            if a + b + c + d + e + f + g == 0:
                break


TPL_RE = re.compile(r'^\?\$')


def demangle_msvc_type(s):
    """'CGameSprite@@' -> 'CGameSprite'; 'Inner@Outer@@' -> 'Outer::Inner'. Templates -> None."""
    if not s.endswith('@@') or '?' in s or '$' in s:
        return None
    parts = s[:-2].split('@')
    if any(not p for p in parts):
        return None
    return '::'.join(reversed(parts))


def apply_overrides(M, ov, log):
    """Manual verification results: {"set": {linux name: win rva}, "set_alias": {rva: [names]}, "reject_win": [rva]}."""
    L = M.L
    byn = {f['name']: a for a, f in L.funcs.items()}

    def unmatch_w(w, keep=()):
        for l in list(M.inv.get(w, ())):
            if l not in keep:
                del M.m[l]
                M.inv[w].discard(l)
        if not M.inv.get(w):
            M.inv.pop(w, None)
    n = 0
    for w in ov.get('reject_win', []):
        unmatch_w(int(w, 16))
        n += 1
    for name, w in ov.get('set', {}).items():
        w = int(w, 16)
        l = byn.get(name)
        if l is None:
            continue
        if l in M.m:
            ow = M.m.pop(l)[0]
            M.inv[ow].discard(l)
            if not M.inv[ow]:
                M.inv.pop(ow)
        keep = {byn[x] for x in ov.get('set_alias', {}).get(hex(w), []) if x in byn}
        unmatch_w(w, keep)
        M.add(l, w, 'high', 'manual-verified')
        for k in keep:
            if k not in M.m:
                M.add(k, w, 'medium', 'manual-verified (inlined into)')
        n += 1
    log(f'overrides applied: {n}')


def main():
    lp, wp, out = sys.argv[1:4]
    rep = sys.argv[sys.argv.index('--report') + 1] if '--report' in sys.argv else None
    L = pickle.load(open(lp, 'rb'))
    W = pickle.load(open(wp, 'rb'))
    M = Matcher(L, W)
    lines = []

    def log(s):
        print(s)
        lines.append(s)
    ov = json.load(open(sys.argv[sys.argv.index('--overrides') + 1])) if '--overrides' in sys.argv else None
    M.run(log, ov)
    if ov:
        apply_overrides(M, ov, log)
    res = []
    for w, ls in sorted(M.inv.items()):
        ls = [x for x in ls if not L.funcs[x].get('static')]
        if not ls:
            continue
        ls = sorted(ls, key=lambda l: (-CONF_RANK[M.m[l][1]], L.funcs[l]['name']))
        l0 = ls[0]
        _, conf, meth = M.m[l0]
        if len(ls) > 1:
            conf = 'low' if conf != 'high' else 'medium'
            meth += f' (+{len(ls) - 1} folded)'
        e = {'name': L.funcs[l0]['name'], 'demangled': L.funcs[l0]['dem'], 'addr': hex(w),
             'confidence': conf, 'method': meth, 'linux_addr': hex(l0)}
        if len(ls) > 1:
            e['aliases'] = [L.funcs[x]['name'] for x in ls[1:]]
        res.append(e)
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(res, f, indent=1)
    named = sum(1 for x in M.m if not L.funcs[x].get('static'))
    log(f'{len(res)} windows functions named ({named} named + {len(M.m) - named} static linux functions matched)')
    log(f'linux functions: {len(L.funcs)}  windows functions: {len(W.funcs)}')
    log(f"by confidence: {dict(collections.Counter(e['confidence'] for e in res))}")
    with open(out + '.pairs.pkl', 'wb') as f:
        pickle.dump(M.m, f)
    if rep:
        open(rep, 'w').write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
