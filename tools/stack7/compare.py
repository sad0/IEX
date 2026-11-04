"""Compares the stack7 probe results of EEex and IEX runs (<dir>/eeex-runN.txt, <dir>/iex-runN.txt).

Writes <dir>/compare.md and prints a summary. Keys starting with 'nd.' are random or timing dependent: listed with
both values, never counted as differences. A key whose runs of one side disagree is 'nondeterministic'.
Usage: python -I compare.py <dir> [--side-b iex|linux]
"""
import glob
import os
import re
import sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')


def load(path):
    d = {}
    for line in open(path, encoding='utf-8', errors='replace'):
        line = line.rstrip('\n')
        if ' = ' not in line:
            continue
        k, v = line.split(' = ', 1)
        d[k] = v
    return d


def main():
    out = sys.argv[1]
    side_b = 'iex'
    if '--side-b' in sys.argv:
        side_b = sys.argv[sys.argv.index('--side-b') + 1]
    runs = {}
    for side in ('eeex', side_b):
        runs[side] = [load(p) for p in sorted(glob.glob(os.path.join(out, side + '-run*.txt'))) if re.search(r'-run\d+\.txt$', p)]
    a, b = runs['eeex'], runs[side_b]
    if not a or not b:
        sys.exit('need runs of both sides in ' + out)
    keys = sorted(set().union(*[r.keys() for r in a + b]))
    rows = {'same': [], 'diff': [], 'missing': [], 'extra': [], 'nondet': [], 'nd': []}
    for k in keys:
        va = [r.get(k) for r in a]
        vb = [r.get(k) for r in b]
        if k.startswith('nd.'):
            rows['nd'].append((k, va, vb))
            continue
        if len(set(va)) > 1 or len(set(vb)) > 1:
            rows['nondet'].append((k, va, vb))
            continue
        if va[0] is None:
            rows['extra'].append((k, va, vb))
        elif vb[0] is None:
            rows['missing'].append((k, va, vb))
        elif va[0] == vb[0]:
            rows['same'].append((k, va, vb))
        else:
            rows['diff'].append((k, va, vb))
    lines = ['# Stack7 probe: EEex vs %s (%s)' % (side_b, os.path.basename(out)), '',
             '| Class | Keys |', '|---|---|']
    for c in ('diff', 'missing', 'extra', 'nondet', 'same', 'nd'):
        lines.append('| %s | %d |' % (c, len(rows[c])))
    lines.append('')

    def short(v, n=600):
        v = str(v)
        return v if len(v) <= n else v[:n] + '...'
    for c in ('diff', 'missing', 'extra', 'nondet', 'nd'):
        if not rows[c]:
            continue
        lines += ['## ' + c, '']
        for k, va, vb in rows[c]:
            lines.append('- `%s`' % k)
            lines.append('  - EEex: `%s`' % short(' || '.join(map(str, va))))
            lines.append('  - %s: `%s`' % (side_b, short(' || '.join(map(str, vb)))))
        lines.append('')
    open(os.path.join(out, 'compare.md'), 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
    print(' '.join('%s=%d' % (c, len(rows[c])) for c in rows))
    for k, va, vb in rows['diff'] + rows['missing'] + rows['extra']:
        print('%-8s %s\n   eeex: %s\n   %s: %s' % ('DIFF' if va[0] and vb[0] else 'ONLY', k, short(va[0], 300), side_b,
                                                    short(vb[0], 300)))


if __name__ == '__main__':
    main()
