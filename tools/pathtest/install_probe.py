"""Installs the pathfinding test probe in a test copy's override: python -I install_probe.py <override dir>.

M_IEXPTH.lua = probe/pth_body.lua wrapped in load() + pcall (a load error never reaches the engine: under EEex a
Lua error in an M_ file opens a modal popup); PTH.menu = the per-frame tick menu.
"""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'difftest'))
from gen_cases import wrap  # noqa: E402


def main():
    dst = sys.argv[1]
    with open(os.path.join(HERE, 'probe', 'pth_body.lua'), encoding='utf-8') as f:
        src = f.read()
    text = wrap(src, 'M_IEXPTH.lua').replace('difftest_status.txt', 'pathtest_status.txt').replace('DIFFT|', 'PTH|')
    with open(os.path.join(dst, 'M_IEXPTH.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    shutil.copy(os.path.join(HERE, 'probe', 'PTH.menu'), os.path.join(dst, 'PTH.menu'))


if __name__ == '__main__':
    main()
