"""Updates IEX in an existing test game folder from this repo (no WeiDU reinstall): IEX.dll / IEXLauncher.exe from a
build dir, IEX/*.lua, IEX/engine/*.iexd, IEX/IEX_API.txt and the UI menus (IEX/ui and override). Old files are
deleted first, so hardlinks to other copies are never written through. The game must be closed.

Usage: python -I tools/deploy_build.py <game dir> [<build dir>]   (build dir default: build-bgbot)
"""
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
KEEP = {'live.lua'}  # test-copy files that are not from the repo


def put(src, dst):
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        dst.unlink()
    shutil.copy2(src, dst)


def main():
    game = pathlib.Path(sys.argv[1])
    build = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / 'build-bgbot'
    for name in ('IEX.dll', 'IEXLauncher.exe'):
        put(build / name, game / name)
    iex = game / 'IEX'
    for old in iex.glob('*.lua'):
        if old.name not in KEEP:
            old.unlink()
    for f in (ROOT / 'lua').glob('*.lua'):
        put(f, iex / f.name)
    for f in (ROOT / 'engine').glob('*.iexd'):
        put(f, iex / 'engine' / f.name)
    for f in (ROOT / 'ui').glob('*.menu'):
        put(f, iex / 'ui' / f.name)
        put(f, game / 'override' / f.name)
    subprocess.run([sys.executable, '-I', str(ROOT / 'tools/compat/api_list.py'), str(iex / 'IEX_API.txt')], check=True)
    version = (ROOT / 'VERSION').read_text().strip()
    head = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True).stdout.strip()
    print(f'deployed IEX {version} ({head}) from {build} -> {game}')


if __name__ == '__main__':
    main()
