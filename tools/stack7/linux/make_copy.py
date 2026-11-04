"""Linux twin of tools/difftest/make_copy.py: private copy of an installed game on the WSL disk. Read-only data
(data, movies, music, lang sounds, the executable) is hardlinked; everything a game or mod could write is copied.
Usage (in WSL): python3 -I make_copy.py <source> <dest>"""
import os
import shutil
import sys

LINK_DIRS = {'data', 'movies', 'music'}


def main():
    src, dst = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    if src == dst:
        sys.exit('source and destination are the same')
    if os.path.exists(dst):
        shutil.rmtree(dst)
    n = {'link': 0, 'copy': 0}
    for root, dirs, files in os.walk(src):
        rel = os.path.relpath(root, src)
        top = '' if rel == '.' else rel.split(os.sep)[0].lower()
        for name in files:
            s = os.path.join(root, name)
            d = os.path.join(dst, name) if rel == '.' else os.path.join(dst, rel, name)
            os.makedirs(os.path.dirname(d), exist_ok=True)
            low = name.lower()
            link = top in LINK_DIRS or (top == 'lang' and not low.endswith(('.tlk', '.ini', '.lua', '.2da'))) or \
                (top == '' and low in ('baldursgateii', 'libsteam_api.so'))
            if link:
                try:
                    os.link(s, d)
                    n['link'] += 1
                    continue
                except OSError:
                    pass
            shutil.copy2(s, d)
            n['copy'] += 1
    print('copy done: %d hardlinks, %d copies -> %s' % (n['link'], n['copy'], dst))


if __name__ == '__main__':
    main()
