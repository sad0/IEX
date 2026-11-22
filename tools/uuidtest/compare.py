"""Compares two outputs of tools/uuidtest (EEex vs IEX, or two saves) after removing what legitimately differs:
object ids, function addresses, Lua file:line prefixes of error messages, the engine line, and pairs() order
(lines are sorted inside each "---" / "===" section, items inside {...}). Known EEex-only line: "marshal handlers:
EEex" (EEex registers a marshal handler of its own; IEX has none). Exit code 0 = same.

Usage: python -I compare.py <a.txt> <b.txt>
"""
import re
import sys


def sections(path):
    out, cur, title = [], [], ''
    for raw in open(path, encoding='utf-8', errors='replace'):
        line = raw.rstrip('\n')
        if line.startswith('engine '):
            continue
        line = re.sub(r'id=\d+ ?', '', line)
        line = re.sub(r'function: (0x)?[0-9A-Fa-f]+', 'function', line)
        line = re.sub(r'ERROR [^ ]+\.lua:\d+: ', 'ERROR ', line)
        line = re.sub(r'ERROR uuidt:\d+: ', 'ERROR ', line)
        line = re.sub(r'ERROR EEex_Sprite_GetFromUUID: .*', 'ERROR (bad argument)', line)
        line = re.sub(r"ERROR invalid type .* in function 'GetSpriteFromUUID'.*", 'ERROR (bad argument)', line)
        line = re.sub(r"attempt to index local '\w+'", "attempt to index local", line)
        # pairs() order inside the table dumps of the probe: {a; b; c}
        line = re.sub(r'\{([^{}]*)\}', lambda m: '{' + '; '.join(sorted(m.group(1).split('; '))) + '}', line)
        if line.startswith(('---', '===')) or not line.startswith(' '):
            out.append((title, sorted(cur)))
            title, cur = line, []
        else:
            cur.append(line)
    out.append((title, sorted(cur)))
    return out


def main():
    a, b = sections(sys.argv[1]), sections(sys.argv[2])
    diffs = 0
    for i in range(max(len(a), len(b))):
        ta, la = a[i] if i < len(a) else ('(missing)', [])
        tb, lb = b[i] if i < len(b) else ('(missing)', [])
        if ta != tb or la != lb:
            diffs += 1
            print(f'@@ section {i}')
            print(f'  A: {ta}')
            print(f'  B: {tb}')
            for x in sorted(set(la) - set(lb)):
                print(f'  - {x}')
            for x in sorted(set(lb) - set(la)):
                print(f'  + {x}')
    print('same' if not diffs else f'{diffs} section(s) differ')
    sys.exit(1 if diffs else 0)


if __name__ == '__main__':
    main()
