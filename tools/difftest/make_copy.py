"""Makes a private test copy of an installed game for the differential test.

Big read-only data (BIFs, movies, music, sounds) is hardlinked; everything the game, the probe or a mod could
write (top-level files, override, dialog.tlk, chitin.key, WeiDU.log, ini/lua files) is a real copy, so the
source game is never modified. Run with `python -I make_copy.py <source> <dest>`.
Re-running refreshes the copy (deletes <dest> first).
"""
import os
import shutil
import sys

# Folders whose files are hardlinked (never written by the engine).
LINK_DIRS = {'data', 'movies', 'music', 'eet', 'weidu_external', 'manuals', 'eet_end', 'bgbot'}
# Folders skipped entirely.
SKIP_DIRS = {'infinityloader_crash'}
# Files that are always copied, wherever they are.
# IEX binaries too: each copy gets its own build, and writing through a hardlink would change every copy.
COPY_NAMES = {'dialog.tlk', 'dialogf.tlk', 'chitin.key', 'weidu.log', 'iex.dll', 'iexlauncher.exe'}
# Large top-level files that the game never writes.
LINK_EXT = {'.exe', '.dll', '.bif'}  # not .debug: WeiDU rewrites SETUP-*.DEBUG logs


def place(src, dst, link):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if link:
        try:
            os.link(src, dst)
            return 'link'
        except OSError:
            pass
    shutil.copy2(src, dst)
    return 'copy'


def main():
    src, dst = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    if os.path.normcase(src) == os.path.normcase(dst):
        sys.exit('source and destination are the same')
    if os.path.exists(dst):
        shutil.rmtree(dst)
    counts = {'link': 0, 'copy': 0}
    for root, dirs, files in os.walk(src):
        rel = os.path.relpath(root, src)
        top = '' if rel == '.' else rel.split(os.sep)[0].lower()
        if top in SKIP_DIRS:
            dirs[:] = []
            continue
        for name in files:
            low = name.lower()
            s = os.path.join(root, name)
            d = os.path.join(dst, rel, name) if rel != '.' else os.path.join(dst, name)
            if low in COPY_NAMES:
                link = False
            elif top in LINK_DIRS:
                link = True
            elif top == 'lang':
                # Sounds are big and read-only; tlk files are copied above.
                link = not low.endswith(('.tlk', '.ini', '.lua', '.2da'))
            elif top == '':
                link = os.path.splitext(low)[1] in LINK_EXT
            else:
                link = False  # override, EEex folders, IEX, mod folders: real copies
            counts[place(s, d, link)] += 1
    print('copy done: %d hardlinks, %d copies -> %s' % (counts['link'], counts['copy'], dst))


if __name__ == '__main__':
    main()
